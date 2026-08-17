#include <ruby.h>
#include <ruby/encoding.h>
#include <ruby/st.h>

#include <stdbool.h>
#include <stdint.h>
#include <string.h>

#include "file_serialization.h"

// Bulk file serialization is independent from coverage collection. It packs
// large file lists without building normalized intermediate Ruby collections.

struct packed_files_context {
  VALUE root;
  VALUE seen;
  VALUE packed;
  long root_len;
  uint32_t files_count;
  bool direct_absolute;
  bool supported;
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

static void packed_files_append_u16(VALUE packed, uint16_t value) {
  unsigned char bytes[2] = {(unsigned char)(value >> 8),
                            (unsigned char)value};
  rb_str_cat(packed, (const char *)bytes, 2);
}

static void packed_files_append_u32(VALUE packed, uint32_t value) {
  unsigned char bytes[4] = {
      (unsigned char)(value >> 24), (unsigned char)(value >> 16),
      (unsigned char)(value >> 8), (unsigned char)value};
  rb_str_cat(packed, (const char *)bytes, 4);
}

static void packed_files_append_string_header(VALUE packed, uint32_t len,
                                              bool binary) {
  unsigned char byte;
  if (binary) {
    if (len < 256) {
      byte = 0xc4;
      rb_str_cat(packed, (const char *)&byte, 1);
      byte = (unsigned char)len;
      rb_str_cat(packed, (const char *)&byte, 1);
    } else if (len < 65536) {
      byte = 0xc5;
      rb_str_cat(packed, (const char *)&byte, 1);
      packed_files_append_u16(packed, (uint16_t)len);
    } else {
      byte = 0xc6;
      rb_str_cat(packed, (const char *)&byte, 1);
      packed_files_append_u32(packed, len);
    }
  } else if (len < 32) {
    byte = (unsigned char)(0xa0U | len);
    rb_str_cat(packed, (const char *)&byte, 1);
  } else if (len < 256) {
    byte = 0xd9;
    rb_str_cat(packed, (const char *)&byte, 1);
    byte = (unsigned char)len;
    rb_str_cat(packed, (const char *)&byte, 1);
  } else if (len < 65536) {
    byte = 0xda;
    rb_str_cat(packed, (const char *)&byte, 1);
    packed_files_append_u16(packed, (uint16_t)len);
  } else {
    byte = 0xdb;
    rb_str_cat(packed, (const char *)&byte, 1);
    packed_files_append_u32(packed, len);
  }
}

static bool packed_files_append_entry(struct packed_files_context *context,
                                      VALUE file, bool additional_file) {
  if (file == Qnil && !additional_file) {
    return true;
  }
  if (!RB_TYPE_P(file, T_STRING) || rb_obj_class(file) != rb_cString) {
    context->supported = false;
    return false;
  }

  VALUE relative_file = file;
  VALUE dedup_file = file;
  const char *relative_ptr = RSTRING_PTR(file);
  long relative_len = RSTRING_LEN(file);
#ifdef _WIN32
  context->supported = false;
  return false;
#else
  const char *file_ptr = RSTRING_PTR(file);
  long file_len = RSTRING_LEN(file);
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
    if (context->direct_absolute) {
      relative_ptr = file_ptr + context->root_len + 1;
    } else {
      relative_file = rb_str_substr(file, context->root_len + 1, file_len);
      dedup_file = relative_file;
      relative_ptr = RSTRING_PTR(relative_file);
    }
  } else if (!additional_file) {
    // Relative primary paths depend on cwd-to-root Pathname semantics. They
    // are uncommon and retain the authoritative Ruby fallback.
    context->supported = false;
    return false;
  }
#endif

  if (relative_len == 0) {
    return true;
  }
  if (rb_hash_lookup2(context->seen, dedup_file, Qundef) != Qundef) {
    return true;
  }
  rb_hash_aset(context->seen, dedup_file, Qtrue);

  int encoding_index = rb_enc_get_index(relative_file);
  bool binary = encoding_index == rb_ascii8bit_encindex();
  if (!binary && encoding_index != rb_utf8_encindex() &&
      encoding_index != rb_usascii_encindex() &&
      !string_bytes_are_ascii(relative_file)) {
    context->supported = false;
    return false;
  }

  if (relative_len > UINT32_MAX) {
    rb_raise(rb_eArgError, "size of filename is too long to pack: %lu bytes",
             (unsigned long)relative_len);
  }

  static const unsigned char filename_entry_prefix[] = {
      0x81, 0xa8, 'f', 'i', 'l', 'e', 'n', 'a', 'm', 'e'};
  rb_str_cat(context->packed, (const char *)filename_entry_prefix,
             sizeof(filename_entry_prefix));
  packed_files_append_string_header(context->packed, (uint32_t)relative_len,
                                    binary);
  rb_str_cat(context->packed, relative_ptr, relative_len);
  context->files_count++;
  return true;
}

static int pack_primary_file_i(VALUE file, VALUE _value,
                               VALUE context_value) {
  struct packed_files_context *context =
      (struct packed_files_context *)context_value;
  return packed_files_append_entry(context, file, false) ? ST_CONTINUE
                                                         : ST_STOP;
}

static bool packed_file_is_absolute(VALUE file, bool additional_file) {
#ifdef _WIN32
  return false;
#else
  if (file == Qnil && !additional_file) {
    return true;
  }
  return RB_TYPE_P(file, T_STRING) && rb_obj_class(file) == rb_cString &&
         RSTRING_LEN(file) > 0 && RSTRING_PTR(file)[0] == '/';
#endif
}

static int detect_absolute_primary_file_i(VALUE file, VALUE _value,
                                          VALUE all_absolute_value) {
  bool *all_absolute = (bool *)all_absolute_value;
  if (!packed_file_is_absolute(file, false)) {
    *all_absolute = false;
    return ST_STOP;
  }
  return ST_CONTINUE;
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

static VALUE file_serialization_pack_files(VALUE module, VALUE primary_files,
                                           VALUE additional_files,
                                           VALUE root) {
  Check_Type(primary_files, T_HASH);
  Check_Type(additional_files, T_ARRAY);
  if (!RB_TYPE_P(root, T_STRING) || rb_obj_class(root) != rb_cString ||
      RSTRING_LEN(root) == 0 || !string_bytes_are_ascii(root)) {
    return Qnil;
  }

  bool all_absolute = true;
  rb_hash_foreach(primary_files, detect_absolute_primary_file_i,
                  (VALUE)&all_absolute);
  long additional_files_len = RARRAY_LEN(additional_files);
  for (long i = 0; all_absolute && i < additional_files_len; i++) {
    all_absolute =
        packed_file_is_absolute(rb_ary_entry(additional_files, i), true);
  }

  struct packed_files_context context = {
      .root = root,
      .seen = rb_hash_new(),
      .packed = rb_str_buf_new(4096),
      .root_len = RSTRING_LEN(root),
      .files_count = 0,
      .direct_absolute = all_absolute,
      .supported = true};
  rb_str_resize(context.packed, 5);

  rb_hash_foreach(primary_files, pack_primary_file_i, (VALUE)&context);
  if (!context.supported) {
    return Qnil;
  }

  for (long i = 0; i < additional_files_len; i++) {
    if (!packed_files_append_entry(&context,
                                   rb_ary_entry(additional_files, i), true)) {
      return Qnil;
    }
  }

  packed_files_write_array_header(&context);
  return context.packed;
}

void Init_file_serialization(void) {
  VALUE mDatadog = rb_define_module("Datadog");
  VALUE mCI = rb_define_module_under(mDatadog, "CI");
  VALUE mFileSerialization =
      rb_define_module_under(mCI, "FileSerialization");

  rb_define_singleton_method(mFileSerialization, "pack_files",
                             file_serialization_pack_files, 3);
}
