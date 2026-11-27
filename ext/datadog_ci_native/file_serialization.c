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
  VALUE packed;
  const char *root_ptr;
  char *buf_ptr;
  long buf_len;
  long buf_cap;
  long root_len;
  int utf8_enc;
  int usascii_enc;
  int bin_enc;
  uint32_t files_count;
  size_t header_reserve;
  bool fast_path_supported;
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

static inline void
packed_files_ensure_capacity(struct packed_files_context *context,
                             long needed) {
  if (context->buf_len + needed <= context->buf_cap) {
    return;
  }

  long min_cap = context->buf_len + needed;
  long new_cap = context->buf_cap * 2;
  if (new_cap < min_cap) {
    new_cap = min_cap;
  }

  rb_str_set_len(context->packed, context->buf_len);
  rb_str_modify_expand(context->packed, new_cap - context->buf_len);
  context->buf_ptr = RSTRING_PTR(context->packed);
  context->root_ptr = RSTRING_PTR(context->root);
  context->buf_cap = (long)rb_str_capacity(context->packed);
}

static inline size_t packed_files_encode_string_header(unsigned char *out,
                                                       uint32_t len,
                                                       bool binary) {
  if (binary) {
    if (len < 256) {
      out[0] = 0xc4;
      out[1] = (unsigned char)len;
      return 2;
    } else if (len < 65536) {
      out[0] = 0xc5;
      out[1] = (unsigned char)(len >> 8);
      out[2] = (unsigned char)len;
      return 3;
    } else {
      out[0] = 0xc6;
      out[1] = (unsigned char)(len >> 24);
      out[2] = (unsigned char)(len >> 16);
      out[3] = (unsigned char)(len >> 8);
      out[4] = (unsigned char)len;
      return 5;
    }
  } else if (len < 32) {
    out[0] = (unsigned char)(0xa0U | len);
    return 1;
  } else if (len < 256) {
    out[0] = 0xd9;
    out[1] = (unsigned char)len;
    return 2;
  } else if (len < 65536) {
    out[0] = 0xda;
    out[1] = (unsigned char)(len >> 8);
    out[2] = (unsigned char)len;
    return 3;
  } else {
    out[0] = 0xdb;
    out[1] = (unsigned char)(len >> 24);
    out[2] = (unsigned char)(len >> 16);
    out[3] = (unsigned char)(len >> 8);
    out[4] = (unsigned char)len;
    return 5;
  }
}

static bool packed_files_append_entry(struct packed_files_context *context,
                                      VALUE file, bool additional_file) {
  if (file == Qnil && !additional_file) {
    return true;
  }
  if (!RB_TYPE_P(file, T_STRING) || RBASIC_CLASS(file) != rb_cString) {
    context->fast_path_supported = false;
    return false;
  }

  const char *file_ptr = RSTRING_PTR(file);
  long file_len = RSTRING_LEN(file);

  long relative_len = file_len;
  long relative_offset = 0;
  bool absolute = file_len > 0 && file_ptr[0] == '/';
  if (absolute) {
    if (file_len <= context->root_len ||
        memcmp(file_ptr, context->root_ptr, (size_t)context->root_len) != 0 ||
        file_ptr[context->root_len] != '/') {
      // Absolute additional files outside the immutable repository root are
      // ignored. Primary files are already filtered by the same root.
      if (memchr(file_ptr, '\0', (size_t)file_len) != NULL) {
        context->fast_path_supported = false;
        return false;
      }
      return true;
    }

    relative_len = file_len - context->root_len - 1;
    if (relative_len == 0) {
      return true;
    }
    relative_offset = context->root_len + 1;
  } else if (!additional_file) {
    // Production DDCov and static-dependency extraction only emit absolute
    // paths after filtering them against the repository root. Keep the Ruby
    // fallback for direct callers that violate this invariant.
    context->fast_path_supported = false;
    return false;
  }

  if (relative_len == 0) {
    return true;
  }

  if (memchr(file_ptr + relative_offset, '\0', (size_t)relative_len) != NULL) {
    context->fast_path_supported = false;
    return false;
  }

  int encoding_index = rb_enc_get_index(file);
  bool binary = encoding_index == context->bin_enc;
  if (!binary && encoding_index != context->utf8_enc &&
      encoding_index != context->usascii_enc &&
      (!rb_enc_str_asciicompat_p(file) || !string_bytes_are_ascii(file))) {
    context->fast_path_supported = false;
    return false;
  }

  if (relative_len > UINT32_MAX) {
    rb_raise(rb_eArgError, "size of filename is too long to pack: %lu bytes",
             (unsigned long)relative_len);
  }

  static const unsigned char filename_entry_prefix[] = {
      0x81, 0xa8, 'f', 'i', 'l', 'e', 'n', 'a', 'm', 'e'};
  unsigned char str_header[5];
  size_t str_header_len = packed_files_encode_string_header(
      str_header, (uint32_t)relative_len, binary);

  long entry_len = (long)(sizeof(filename_entry_prefix) + str_header_len) +
                   relative_len;
  packed_files_ensure_capacity(context, entry_len);

  // Re-fetch RSTRING_PTR(file) after potential GC during buffer expansion.
  const char *relative_ptr = RSTRING_PTR(file) + relative_offset;
  char *dst = context->buf_ptr + context->buf_len;
  memcpy(dst, filename_entry_prefix, sizeof(filename_entry_prefix));
  memcpy(dst + sizeof(filename_entry_prefix), str_header, str_header_len);
  memcpy(dst + sizeof(filename_entry_prefix) + str_header_len, relative_ptr,
         (size_t)relative_len);

  context->buf_len += entry_len;
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

  long body_len = context->buf_len - (long)context->header_reserve;
  char *packed_ptr = context->buf_ptr;
  if (header_len != context->header_reserve) {
    memmove(packed_ptr + header_len, packed_ptr + context->header_reserve,
            (size_t)body_len);
  }
  memcpy(packed_ptr, header, header_len);
  rb_str_set_len(context->packed, body_len + (long)header_len);
}

static VALUE file_serialization_pack_files(VALUE module, VALUE primary_files,
                                           VALUE additional_files,
                                           VALUE root) {
  Check_Type(primary_files, T_HASH);
  Check_Type(additional_files, T_ARRAY);
  if (!RB_TYPE_P(root, T_STRING) || RBASIC_CLASS(root) != rb_cString ||
      RSTRING_LEN(root) == 0 || !string_bytes_are_ascii(root) ||
      memchr(RSTRING_PTR(root), '\0', (size_t)RSTRING_LEN(root)) != NULL) {
    return Qnil;
  }

  long additional_files_len = RARRAY_LEN(additional_files);
  size_t max_files =
      (size_t)RHASH_SIZE(primary_files) + (size_t)additional_files_len;
  size_t header_reserve =
      max_files < 16 ? 1 : (max_files < 65536 ? 3 : 5);
  size_t initial_cap = max_files * 64 + 16;
  if (initial_cap < 256) {
    initial_cap = 256;
  } else if (initial_cap > 4 * 1024 * 1024) {
    initial_cap = 4 * 1024 * 1024;
  }

  VALUE packed = rb_str_buf_new((long)initial_cap);
  struct packed_files_context context = {
      .root = root,
      .packed = packed,
      .root_ptr = RSTRING_PTR(root),
      .buf_ptr = RSTRING_PTR(packed),
      .buf_len = (long)header_reserve,
      .buf_cap = (long)rb_str_capacity(packed),
      .root_len = RSTRING_LEN(root),
      .utf8_enc = rb_utf8_encindex(),
      .usascii_enc = rb_usascii_encindex(),
      .bin_enc = rb_ascii8bit_encindex(),
      .files_count = 0,
      .header_reserve = header_reserve,
      .fast_path_supported = true};

  rb_hash_foreach(primary_files, pack_primary_file_i, (VALUE)&context);
  if (!context.fast_path_supported) {
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
