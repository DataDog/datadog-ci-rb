#include <ruby.h>
#include <ruby/encoding.h>
#include <ruby/st.h>

#include <limits.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

#include "file_serialization.h"

// Bulk file serialization is independent from coverage collection. It packs
// large file lists without building normalized intermediate Ruby collections.

struct packed_file_key;

struct packed_files_context {
  VALUE primary_files;
  VALUE additional_files;
  VALUE static_dependencies;
  VALUE root;
  VALUE relative_path_prefix;
  VALUE packed;
  st_table *seen;
  struct packed_file_key *seen_keys;
  char *lookup_buffer;
  long lookup_buffer_capacity;
  long seen_keys_capacity;
  long seen_keys_count;
  long root_len;
  long relative_path_prefix_len;
  uint32_t files_count;
  bool fast_path_supported;
};

// Deduplication keys point at bytes already written to the output buffer. The
// lookup key is temporary and points at the current Ruby String only while no
// allocating Ruby API is running. This avoids copying or interning filenames
// merely to use them as Hash keys.
struct packed_file_key {
  struct packed_files_context *context;
  const char *lookup_ptr;
  long packed_offset;
  long len;
  int encoding_index;
  st_index_t hash;
  bool stored;
};

static bool string_bytes_are_ascii(VALUE string) {
  const unsigned char *ptr = (const unsigned char *)RSTRING_PTR(string);
  long len = RSTRING_LEN(string);
  for (long i = 0; i < len; i++) {
    if ((ptr[i] & 0x80U) != 0) {
      return false;
    }
  }
  return true;
}

static const char *packed_file_key_bytes(const struct packed_file_key *key) {
  if (key->stored) {
    return RSTRING_PTR(key->context->packed) + key->packed_offset;
  }
  return key->lookup_ptr;
}

static bool bytes_are_ascii(const char *ptr, long len) {
  for (long i = 0; i < len; i++) {
    if (((unsigned char)ptr[i] & 0x80U) != 0) {
      return false;
    }
  }
  return true;
}

static int packed_file_key_compare(st_data_t left_value,
                                   st_data_t right_value) {
  const struct packed_file_key *left =
      (const struct packed_file_key *)left_value;
  const struct packed_file_key *right =
      (const struct packed_file_key *)right_value;
  if (left->len != right->len) {
    return 1;
  }

  const char *left_ptr = packed_file_key_bytes(left);
  const char *right_ptr = packed_file_key_bytes(right);
  if (memcmp(left_ptr, right_ptr, (size_t)left->len) != 0) {
    return 1;
  }

  // Ruby Strings with identical ASCII bytes compare as hash keys even when
  // their ASCII-compatible encodings differ. Non-ASCII bytes also require the
  // same encoding. All unsupported encodings are rejected before lookup.
  if (left->encoding_index == right->encoding_index ||
      bytes_are_ascii(left_ptr, left->len)) {
    return 0;
  }
  return 1;
}

static st_index_t packed_file_key_hash(st_data_t key_value) {
  const struct packed_file_key *key =
      (const struct packed_file_key *)key_value;
  return key->hash;
}

static const struct st_hash_type packed_file_key_hash_type = {
    packed_file_key_compare, packed_file_key_hash};

static void packed_files_write_u16(unsigned char *bytes, uint16_t value) {
  bytes[0] = (unsigned char)(value >> 8);
  bytes[1] = (unsigned char)value;
}

static void packed_files_write_u32(unsigned char *bytes, uint32_t value) {
  bytes[0] = (unsigned char)(value >> 24);
  bytes[1] = (unsigned char)(value >> 16);
  bytes[2] = (unsigned char)(value >> 8);
  bytes[3] = (unsigned char)value;
}

static size_t packed_files_write_string_header(unsigned char *header,
                                               uint32_t len, bool binary) {
  if (binary) {
    if (len < 256) {
      header[0] = 0xc4;
      header[1] = (unsigned char)len;
      return 2;
    } else if (len < 65536) {
      header[0] = 0xc5;
      packed_files_write_u16(header + 1, (uint16_t)len);
      return 3;
    } else {
      header[0] = 0xc6;
      packed_files_write_u32(header + 1, len);
      return 5;
    }
  } else if (len < 32) {
    header[0] = (unsigned char)(0xa0U | len);
    return 1;
  } else if (len < 256) {
    header[0] = 0xd9;
    header[1] = (unsigned char)len;
    return 2;
  } else if (len < 65536) {
    header[0] = 0xda;
    packed_files_write_u16(header + 1, (uint16_t)len);
    return 3;
  } else {
    header[0] = 0xdb;
    packed_files_write_u32(header + 1, len);
    return 5;
  }
}

static bool packed_files_append_entry(struct packed_files_context *context,
                                      VALUE file, bool additional_file,
                                      bool check_seen) {
  if (file == Qnil && !additional_file) {
    return true;
  }
  if (!RB_TYPE_P(file, T_STRING) || rb_obj_class(file) != rb_cString) {
    context->fast_path_supported = false;
    return false;
  }

  long relative_offset = 0;
  long relative_len = RSTRING_LEN(file);
  long prefix_len = 0;
  const char *file_ptr = RSTRING_PTR(file);
  long file_len = RSTRING_LEN(file);
  if (memchr(file_ptr, '\0', (size_t)file_len) != NULL) {
    context->fast_path_supported = false;
    return false;
  }
  bool absolute = file_len > 0 && file_ptr[0] == '/';
  if (absolute) {
    if (file_len <= context->root_len ||
        memcmp(file_ptr, RSTRING_PTR(context->root),
               (size_t)context->root_len) != 0 ||
        file_ptr[context->root_len] != '/') {
      // Absolute additional files outside the immutable repository root are
      // ignored. Primary files are already filtered by the same root.
      return true;
    }

    relative_len = file_len - context->root_len - 1;
    if (relative_len == 0) {
      return true;
    }
    relative_offset = context->root_len + 1;
  } else if (!additional_file) {
    // Relative primary paths depend on cwd-to-root Pathname semantics. They
    // are uncommon and retain the authoritative Ruby fallback.
    context->fast_path_supported = false;
    return false;
  } else {
    if (relative_len >= 2 && file_ptr[0] == '.' && file_ptr[1] == '/') {
      relative_offset = 2;
      relative_len -= 2;
    }
    prefix_len = context->relative_path_prefix_len;
  }

  if (relative_len == 0) {
    return true;
  }
  if (prefix_len > LONG_MAX - relative_len) {
    rb_raise(rb_eArgError, "size of filename is too long to pack");
  }
  long packed_relative_len = prefix_len + relative_len;
  int encoding_index = rb_enc_get_index(file);
  bool binary = encoding_index == rb_ascii8bit_encindex();
  if (!binary && encoding_index != rb_utf8_encindex() &&
      encoding_index != rb_usascii_encindex() &&
      (!rb_enc_str_asciicompat_p(file) || !string_bytes_are_ascii(file))) {
    context->fast_path_supported = false;
    return false;
  }
  if (prefix_len > 0 && string_bytes_are_ascii(file)) {
    // File.join uses the prefix encoding when the relative filename is ASCII.
    // The cached prefix is UTF-8, so MessagePack should emit a String rather
    // than a Binary value even for an ASCII-only ASCII-8BIT input.
    encoding_index = rb_enc_get_index(context->relative_path_prefix);
    binary = false;
  }

  if (packed_relative_len > UINT32_MAX) {
    rb_raise(rb_eArgError, "size of filename is too long to pack: %lu bytes",
             (unsigned long)packed_relative_len);
  }

  const char *lookup_ptr;
  if (prefix_len > 0) {
    if (context->lookup_buffer_capacity < packed_relative_len) {
      if (context->lookup_buffer == NULL) {
        context->lookup_buffer = ALLOC_N(char, packed_relative_len);
      } else {
        REALLOC_N(context->lookup_buffer, char, packed_relative_len);
      }
      context->lookup_buffer_capacity = packed_relative_len;
    }
    memcpy(context->lookup_buffer,
           RSTRING_PTR(context->relative_path_prefix), (size_t)prefix_len);
    file_ptr = RSTRING_PTR(file);
    memcpy(context->lookup_buffer + prefix_len, file_ptr + relative_offset,
           (size_t)relative_len);
    lookup_ptr = context->lookup_buffer;
  } else {
    lookup_ptr = RSTRING_PTR(file) + relative_offset;
  }
  struct packed_file_key lookup_key = {
      .context = context,
      .lookup_ptr = lookup_ptr,
      .packed_offset = 0,
      .len = packed_relative_len,
      .encoding_index = encoding_index,
      .hash = rb_memhash(lookup_ptr, packed_relative_len),
      .stored = false};
  if (check_seen &&
      st_lookup(context->seen, (st_data_t)&lookup_key, NULL)) {
    return true;
  }

  unsigned char filename_entry_header[15] = {
      0x81, 0xa8, 'f', 'i', 'l', 'e', 'n', 'a', 'm', 'e'};
  size_t string_header_len = packed_files_write_string_header(
      filename_entry_header + 10, (uint32_t)packed_relative_len, binary);
  rb_str_cat(context->packed, (const char *)filename_entry_header,
             10 + string_header_len);
  long packed_offset = RSTRING_LEN(context->packed);
  if (prefix_len > 0) {
    rb_str_cat(context->packed, context->lookup_buffer, packed_relative_len);
  } else {
    // rb_str_cat can allocate and compact Ruby objects. Resolve the input
    // pointer only after the last preceding allocation.
    file_ptr = RSTRING_PTR(file);
    rb_str_cat(context->packed, file_ptr + relative_offset, relative_len);
  }

  if (context->seen_keys_count >= context->seen_keys_capacity) {
    rb_raise(rb_eRuntimeError, "file serialization deduplication capacity exceeded");
  }
  struct packed_file_key *stored_key =
      &context->seen_keys[context->seen_keys_count++];
  *stored_key = lookup_key;
  stored_key->lookup_ptr = NULL;
  stored_key->packed_offset = packed_offset;
  stored_key->stored = true;
  st_add_direct(context->seen, (st_data_t)stored_key, Qtrue);

  RB_GC_GUARD(file);
  context->files_count++;
  return true;
}

static int pack_primary_file_i(VALUE file, VALUE _value,
                               VALUE context_value) {
  struct packed_files_context *context =
      (struct packed_files_context *)context_value;
  return packed_files_append_entry(context, file, false, false) ? ST_CONTINUE
                                                                : ST_STOP;
}

static int pack_static_dependency_i(VALUE file, VALUE _value,
                                    VALUE context_value) {
  struct packed_files_context *context =
      (struct packed_files_context *)context_value;
  return packed_files_append_entry(context, file, false, true) ? ST_CONTINUE
                                                               : ST_STOP;
}

static void
packed_files_write_array_header(struct packed_files_context *context) {
  unsigned char header[5];
  size_t header_len;
  if (context->files_count < 16) {
    header[0] = (unsigned char)(0x90U | context->files_count);
    header_len = 1;
  } else if (context->files_count < 65536) {
    header[0] = 0xdc;
    header[1] = (unsigned char)(context->files_count >> 8);
    header[2] = (unsigned char)context->files_count;
    header_len = 3;
  } else {
    header[0] = 0xdd;
    header[1] = (unsigned char)(context->files_count >> 24);
    header[2] = (unsigned char)(context->files_count >> 16);
    header[3] = (unsigned char)(context->files_count >> 8);
    header[4] = (unsigned char)context->files_count;
    header_len = 5;
  }

  long body_len = RSTRING_LEN(context->packed) - 5;
  char *packed_ptr = RSTRING_PTR(context->packed);
  if (header_len != 5) {
    memmove(packed_ptr + header_len, packed_ptr + 5, (size_t)body_len);
    rb_str_resize(context->packed, body_len + (long)header_len);
    packed_ptr = RSTRING_PTR(context->packed);
  }
  memcpy(packed_ptr, header, header_len);
}

static VALUE file_serialization_pack_files_body(VALUE context_value) {
  struct packed_files_context *context =
      (struct packed_files_context *)context_value;
  context->seen = st_init_table_with_size(
      &packed_file_key_hash_type, (st_index_t)context->seen_keys_capacity);
  if (context->seen_keys_capacity > 0) {
    context->seen_keys =
        ALLOC_N(struct packed_file_key, context->seen_keys_capacity);
  }
  context->packed = rb_str_buf_new(4096);
  rb_str_resize(context->packed, 5);

  rb_hash_foreach(context->primary_files, pack_primary_file_i,
                  (VALUE)context);
  if (!context->fast_path_supported) {
    return Qnil;
  }

  long static_dependencies_len = context->static_dependencies == Qnil
                                     ? 0
                                     : RARRAY_LEN(context->static_dependencies);
  for (long i = 0; i < static_dependencies_len; i++) {
    rb_hash_foreach(rb_ary_entry(context->static_dependencies, i),
                    pack_static_dependency_i, (VALUE)context);
    if (!context->fast_path_supported) {
      return Qnil;
    }
  }

  long additional_files_len = RARRAY_LEN(context->additional_files);
  for (long i = 0; i < additional_files_len; i++) {
    if (!packed_files_append_entry(
            context, rb_ary_entry(context->additional_files, i), true, true)) {
      return Qnil;
    }
  }

  packed_files_write_array_header(context);
  return context->packed;
}

static VALUE file_serialization_pack_files_cleanup(VALUE context_value) {
  struct packed_files_context *context =
      (struct packed_files_context *)context_value;
  if (context->seen != NULL) {
    st_free_table(context->seen);
  }
  if (context->seen_keys != NULL) {
    xfree(context->seen_keys);
  }
  if (context->lookup_buffer != NULL) {
    xfree(context->lookup_buffer);
  }
  return Qnil;
}

static VALUE file_serialization_pack_files(int argc, VALUE *argv,
                                           VALUE module) {
  VALUE primary_files;
  VALUE additional_files;
  VALUE root;
  VALUE static_dependencies = Qnil;
  VALUE relative_path_prefix = Qnil;
  rb_scan_args(argc, argv, "32", &primary_files, &additional_files, &root,
               &static_dependencies, &relative_path_prefix);

  Check_Type(primary_files, T_HASH);
  Check_Type(additional_files, T_ARRAY);
  if (static_dependencies != Qnil) {
    Check_Type(static_dependencies, T_ARRAY);
  }
  if (!RB_TYPE_P(root, T_STRING) || rb_obj_class(root) != rb_cString ||
      RSTRING_LEN(root) == 0 || !string_bytes_are_ascii(root)) {
    return Qnil;
  }
  if (relative_path_prefix != Qnil &&
      (!RB_TYPE_P(relative_path_prefix, T_STRING) ||
       rb_obj_class(relative_path_prefix) != rb_cString ||
       !string_bytes_are_ascii(relative_path_prefix) ||
       memchr(RSTRING_PTR(relative_path_prefix), '\0',
              (size_t)RSTRING_LEN(relative_path_prefix)) != NULL ||
       (RSTRING_LEN(relative_path_prefix) > 0 &&
        RSTRING_PTR(relative_path_prefix)[RSTRING_LEN(relative_path_prefix) - 1] != '/'))) {
    return Qnil;
  }

  long static_dependencies_len =
      static_dependencies == Qnil ? 0 : RARRAY_LEN(static_dependencies);
  long seen_keys_capacity = RHASH_SIZE(primary_files);
  for (long i = 0; i < static_dependencies_len; i++) {
    VALUE dependencies = rb_ary_entry(static_dependencies, i);
    Check_Type(dependencies, T_HASH);
    long dependencies_size = RHASH_SIZE(dependencies);
    if (seen_keys_capacity > LONG_MAX - dependencies_size) {
      rb_raise(rb_eArgError, "too many files to serialize");
    }
    seen_keys_capacity += dependencies_size;
  }
  long additional_files_len = RARRAY_LEN(additional_files);
  if (seen_keys_capacity > LONG_MAX - additional_files_len) {
    rb_raise(rb_eArgError, "too many files to serialize");
  }
  seen_keys_capacity += additional_files_len;

  struct packed_files_context context = {
      .primary_files = primary_files,
      .additional_files = additional_files,
      .static_dependencies = static_dependencies,
      .root = root,
      .relative_path_prefix = relative_path_prefix,
      .packed = Qnil,
      .seen = NULL,
      .seen_keys = NULL,
      .lookup_buffer = NULL,
      .lookup_buffer_capacity = 0,
      .seen_keys_capacity = seen_keys_capacity,
      .seen_keys_count = 0,
      .root_len = RSTRING_LEN(root),
      .relative_path_prefix_len = relative_path_prefix == Qnil
                                      ? 0
                                      : RSTRING_LEN(relative_path_prefix),
      .files_count = 0,
      .fast_path_supported = true};
  return rb_ensure(file_serialization_pack_files_body, (VALUE)&context,
                   file_serialization_pack_files_cleanup, (VALUE)&context);
}

void Init_file_serialization(void) {
  VALUE mDatadog = rb_define_module("Datadog");
  VALUE mCI = rb_define_module_under(mDatadog, "CI");
  VALUE mFileSerialization =
      rb_define_module_under(mCI, "FileSerialization");

  rb_define_singleton_method(mFileSerialization, "pack_files",
                             file_serialization_pack_files, -1);
}
