#include <ruby.h>
#include <ruby/debug.h>
#include <ruby/encoding.h>
#include <ruby/st.h>

#include <stdbool.h>
#include <string.h>

#include "datadog_common.h"

// This is a native extension that collects a list of Ruby files that were
// executed during the test run. It is used to optimize the test suite by
// running only the tests that are affected by the changes.

#define PROFILE_FRAMES_BUFFER_SIZE 1
#define SEEN_FILENAME_CACHE_SIZE 1024
#define SEEN_ALLOCATED_CLASS_CACHE_SIZE 4096
#define KLASS_FILES_CACHE_SIZE 100000

#if SEEN_FILENAME_CACHE_SIZE == 0 ||                                       \
    (SEEN_FILENAME_CACHE_SIZE & (SEEN_FILENAME_CACHE_SIZE - 1)) != 0
#error "SEEN_FILENAME_CACHE_SIZE must be a power of two"
#endif

#if SEEN_ALLOCATED_CLASS_CACHE_SIZE == 0 ||                               \
    (SEEN_ALLOCATED_CLASS_CACHE_SIZE &                                   \
     (SEEN_ALLOCATED_CLASS_CACHE_SIZE - 1)) != 0
#error "SEEN_ALLOCATED_CLASS_CACHE_SIZE must be a power of two"
#endif

// threading modes
enum threading_mode { single, multi };

// DDCov supports exactly one active collector per process. This process-wide
// invariant keeps coverage ownership deterministic and avoids callback fan-out.
static VALUE active_collector = Qnil;

struct packed_files_context {
  VALUE root;
  VALUE seen;
  VALUE packed;
  long root_len;
  uint32_t files_count;
  bool direct_absolute;
  bool supported;
};


// functions declarations
static void on_newobj_event(VALUE self, const rb_trace_arg_t *tracearg);

static int mark_key_for_gc_i(st_data_t key, st_data_t _value, st_data_t _data) {
  VALUE klass = (VALUE)key;
  // mark klass link for GC as non-movable to avoid changing hashtable's keys
  rb_gc_mark(klass);
  return ST_CONTINUE;
}

static int mark_klass_files_for_gc_i(st_data_t key, st_data_t value,
                                     st_data_t _data) {
  // Both the class key and its cached filenames must remain at stable addresses
  // because they are stored outside Ruby's object containers.
  rb_gc_mark((VALUE)key);
  rb_gc_mark((VALUE)value);
  return ST_CONTINUE;
}

// Data structure
struct dd_cov_data {
  // Ruby hash with filenames impacted by the test.
  VALUE impacted_files;

  // Root is the path to the root folder of the project under test.
  // Files located outside of the root are ignored.
  char *root;
  long root_len;

  // Ignored path contains path to the folder where bundled gems are located if
  // gems are installed in the project folder.
  char *ignored_path;
  long ignored_path_len;

  // Line tracepoint optimisation: make consecutive events from the same file a
  // single comparison, then use a direct-mapped cache for later revisits. Keep
  // the Ruby strings alive so their pointers cannot be reused for other paths.
  // A collision only repeats path processing; it can never suppress coverage.
  VALUE last_filename;
  VALUE seen_filenames[SEEN_FILENAME_CACHE_SIZE];

  // Line tracepoint can work in two modes: single threaded and multi threaded
  //
  // In single threaded mode line tracepoint will only cover the thread that
  // started the coverage. This mode is useful for testing frameworks that run
  // tests in multiple threads. Do not use single threaded mode for Rails
  // applications unless you know that you don't run any background threads.
  //
  // In multi threaded mode line tracepoint will cover all threads. This mode is
  // enabled by default and is recommended for most applications.
  enum threading_mode threading_mode;
  // for single threaded mode: thread that is being covered
  VALUE th_covered;

  // Allocation tracing is used to track test impact for objects that do not
  // contain any methods that could be covered by line tracepoint.
  //
  // Allocation tracing works only in multi threaded mode.
  bool allocation_tracing_enabled;
  bool allocation_hook_active;
  st_table *klasses_table; // { (VALUE) -> int } hashmap with class names that
                           // were covered by allocation during the test run
  VALUE last_allocated_klass;
  VALUE seen_allocated_klasses[SEEN_ALLOCATED_CLASS_CACHE_SIZE];
  st_table *klass_files_cache; // { (VALUE) -> Array<String> } resolved files
  size_t klass_files_cache_size;
};

static void dd_cov_mark(void *ptr) {
  struct dd_cov_data *dd_cov_data = ptr;
  rb_gc_mark_movable(dd_cov_data->impacted_files);
  rb_gc_mark_movable(dd_cov_data->th_covered);

  if (dd_cov_data->last_filename != Qnil) {
    rb_gc_mark(dd_cov_data->last_filename);
  }
  for (size_t i = 0; i < SEEN_FILENAME_CACHE_SIZE; i++) {
    if (dd_cov_data->seen_filenames[i] != Qnil) {
      rb_gc_mark(dd_cov_data->seen_filenames[i]);
    }
  }

  // if GC starts withing dd_cov_allocate() call, klasses_table might not be
  // initialized yet
  if (dd_cov_data->klasses_table != NULL) {
    st_foreach(dd_cov_data->klasses_table, mark_key_for_gc_i, 0);
  }
  if (dd_cov_data->klass_files_cache != NULL) {
    st_foreach(dd_cov_data->klass_files_cache, mark_klass_files_for_gc_i, 0);
  }
}

static void dd_cov_free(void *ptr) {
  struct dd_cov_data *dd_cov_data = ptr;
  xfree(dd_cov_data->root);
  xfree(dd_cov_data->ignored_path);
  st_free_table(dd_cov_data->klasses_table);
  st_free_table(dd_cov_data->klass_files_cache);
  xfree(dd_cov_data);
}

static void dd_cov_compact(void *ptr) {
  struct dd_cov_data *dd_cov_data = ptr;
  dd_cov_data->impacted_files = rb_gc_location(dd_cov_data->impacted_files);
  dd_cov_data->th_covered = rb_gc_location(dd_cov_data->th_covered);
  // keys for dd_cov_data->klasses_table are not moved by GC, so we don't need
  // to update them
}

static const rb_data_type_t dd_cov_data_type = {
    .wrap_struct_name = "dd_cov",
    .function = {.dmark = dd_cov_mark,
                 .dfree = dd_cov_free,
                 .dsize = NULL,
                 .dcompact = dd_cov_compact},
    .flags = RUBY_TYPED_FREE_IMMEDIATELY};

static VALUE dd_cov_allocate(VALUE klass) {
  struct dd_cov_data *dd_cov_data;
  VALUE dd_cov = TypedData_Make_Struct(klass, struct dd_cov_data,
                                       &dd_cov_data_type, dd_cov_data);

  dd_cov_data->impacted_files = rb_hash_new();
  dd_cov_data->root = NULL;
  dd_cov_data->root_len = 0;
  dd_cov_data->ignored_path = NULL;
  dd_cov_data->ignored_path_len = 0;
  dd_cov_data->last_filename = Qnil;
  for (size_t i = 0; i < SEEN_FILENAME_CACHE_SIZE; i++) {
    dd_cov_data->seen_filenames[i] = Qnil;
  }
  dd_cov_data->threading_mode = multi;

  dd_cov_data->allocation_tracing_enabled = false;
  dd_cov_data->allocation_hook_active = false;
  dd_cov_data->last_allocated_klass = Qnil;
  memset(dd_cov_data->seen_allocated_klasses, 0,
         sizeof(dd_cov_data->seen_allocated_klasses));
  // numtable type is needed to store VALUE as a key
  dd_cov_data->klasses_table = st_init_numtable();
  dd_cov_data->klass_files_cache = st_init_numtable();
  dd_cov_data->klass_files_cache_size = 0;

  return dd_cov;
}

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
                                      VALUE file, bool custom_file) {
  if (file == Qnil && !custom_file) {
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
      // Absolute custom files outside the immutable repository root are
      // ignored. Native coverage is already filtered by the same root.
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
  } else if (!custom_file) {
    // Relative native paths depend on cwd-to-root Pathname semantics. They are
    // uncommon and retain the authoritative Ruby fallback.
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
    rb_raise(rb_eArgError,
             "size of coverage filename is too long to pack: %lu bytes",
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

static int pack_native_file_i(VALUE file, VALUE _value, VALUE context_value) {
  struct packed_files_context *context =
      (struct packed_files_context *)context_value;
  return packed_files_append_entry(context, file, false) ? ST_CONTINUE
                                                         : ST_STOP;
}

static bool packed_file_is_absolute(VALUE file, bool custom_file) {
#ifdef _WIN32
  return false;
#else
  if (file == Qnil && !custom_file) {
    return true;
  }
  return RB_TYPE_P(file, T_STRING) && rb_obj_class(file) == rb_cString &&
         RSTRING_LEN(file) > 0 && RSTRING_PTR(file)[0] == '/';
#endif
}

static int detect_absolute_native_file_i(VALUE file, VALUE _value,
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

static VALUE dd_cov_pack_coverage_files(VALUE klass, VALUE coverage,
                                        VALUE custom_files, VALUE root) {
  Check_Type(coverage, T_HASH);
  Check_Type(custom_files, T_ARRAY);
  if (!RB_TYPE_P(root, T_STRING) || rb_obj_class(root) != rb_cString ||
      RSTRING_LEN(root) == 0 || !string_bytes_are_ascii(root)) {
    return Qnil;
  }

  bool all_absolute = true;
  rb_hash_foreach(coverage, detect_absolute_native_file_i,
                  (VALUE)&all_absolute);
  long custom_files_len = RARRAY_LEN(custom_files);
  for (long i = 0; all_absolute && i < custom_files_len; i++) {
    all_absolute =
        packed_file_is_absolute(rb_ary_entry(custom_files, i), true);
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

  rb_hash_foreach(coverage, pack_native_file_i, (VALUE)&context);
  if (!context.supported) {
    return Qnil;
  }

  for (long i = 0; i < custom_files_len; i++) {
    if (!packed_files_append_entry(&context, rb_ary_entry(custom_files, i),
                                   true)) {
      return Qnil;
    }
  }

  packed_files_write_array_header(&context);
  return context.packed;
}

// Helper functions (available in C only)

// Checks if the filename is located under the root folder of the project (but
// not in the ignored folder) and adds it to the impacted_files hash.
static bool record_impacted_file(struct dd_cov_data *dd_cov_data,
                                 VALUE filename) {
  if (!dd_ci_is_path_included(RSTRING_PTR(filename), RSTRING_LEN(filename),
                              dd_cov_data->root, dd_cov_data->root_len,
                              dd_cov_data->ignored_path,
                              dd_cov_data->ignored_path_len)) {
    return false;
  }

  rb_hash_aset(dd_cov_data->impacted_files, filename, Qtrue);
  return true;
}

// Executed on RUBY_EVENT_LINE event and captures the filename from
// rb_profile_frames.
static void on_line_event(rb_event_flag_t event, VALUE data, VALUE self, ID id,
                          VALUE klass) {
  // The hook is registered only with DDCov instances, so the full typed-data
  // type check on every Ruby line is unnecessary.
  struct dd_cov_data *dd_cov_data = RTYPEDDATA_DATA(data);

  const char *c_filename = rb_sourcefile();
  if (c_filename == NULL) {
    return;
  }

  uintptr_t current_filename_ptr = (uintptr_t)c_filename;
  if (dd_cov_data->last_filename != Qnil &&
      RSTRING_PTR(dd_cov_data->last_filename) == c_filename) {
    return;
  }

  size_t cache_index =
      ((current_filename_ptr >> 4) ^ (current_filename_ptr >> 12)) &
      (SEEN_FILENAME_CACHE_SIZE - 1);
  VALUE cached_filename = dd_cov_data->seen_filenames[cache_index];
  if (cached_filename != Qnil && RSTRING_PTR(cached_filename) == c_filename) {
    dd_cov_data->last_filename = cached_filename;
    return;
  }

  VALUE top_frame;
  int captured_frames =
      rb_profile_frames(0 /* stack starting depth */,
                        PROFILE_FRAMES_BUFFER_SIZE, &top_frame, NULL);

  if (captured_frames != PROFILE_FRAMES_BUFFER_SIZE) {
    return;
  }

  VALUE filename = rb_profile_frame_path(top_frame);
  if (filename == Qnil) {
    return;
  }

  dd_cov_data->last_filename = filename;
  dd_cov_data->seen_filenames[cache_index] = filename;
  record_impacted_file(dd_cov_data, filename);
}

// Safely get class name, returns Qnil on any error
static VALUE safely_get_class_name(VALUE klass) {
  return dd_ci_rescue_nil(rb_class_name, klass);
}

// Safely get module ancestors, returns Qnil on any error
static VALUE safely_get_mod_ancestors(VALUE klass) {
  return dd_ci_rescue_nil(rb_mod_ancestors, klass);
}

// This function is called for each class that was instantiated during the test
// run.
static int each_instantiated_klass(st_data_t key, st_data_t _value,
                                   st_data_t data) {
  VALUE klass = (VALUE)key;
  struct dd_cov_data *dd_cov_data = (struct dd_cov_data *)data;

  st_data_t cached_files;
  if (st_lookup(dd_cov_data->klass_files_cache, key, &cached_files)) {
    VALUE files = (VALUE)cached_files;
    long files_len = RARRAY_LEN(files);
    for (long i = 0; i < files_len; i++) {
      rb_hash_aset(dd_cov_data->impacted_files, rb_ary_entry(files, i), Qtrue);
    }
    return ST_CONTINUE;
  }

  VALUE files = rb_ary_new();

  // rb_mod_ancestors returns an array containing the "klass" itself
  // and all the parent classes and/or included/prepended modules
  VALUE ancestors = safely_get_mod_ancestors(klass);
  if (ancestors == Qnil || !RB_TYPE_P(ancestors, T_ARRAY)) {
    return ST_CONTINUE;
  }

  long len = RARRAY_LEN(ancestors);
  for (long i = 0; i < len; i++) {
    VALUE mod = rb_ary_entry(ancestors, i);
    if (mod == Qnil) {
      continue;
    }

    VALUE klass_name = safely_get_class_name(mod);
    if (klass_name == Qnil) {
      continue;
    }

    VALUE filename = dd_ci_resolve_const_to_file(klass_name);
    if (filename == Qnil || !record_impacted_file(dd_cov_data, filename)) {
      continue;
    }

    rb_ary_push(files, filename);
  }

  rb_obj_freeze(files);
  // Bound cross-test retention without adding eviction work to cache hits.
  // Reaching the limit starts a fresh cache generation.
  if (dd_cov_data->klass_files_cache_size >= KLASS_FILES_CACHE_SIZE) {
    st_clear(dd_cov_data->klass_files_cache);
    dd_cov_data->klass_files_cache_size = 0;
  }
  st_insert(dd_cov_data->klass_files_cache, key, (st_data_t)files);
  dd_cov_data->klass_files_cache_size++;

  return ST_CONTINUE;
}

// Executed on RUBY_INTERNAL_EVENT_NEWOBJ event and captures the source file for
// the allocated object's class.
static void on_newobj_event(VALUE self, const rb_trace_arg_t *tracearg) {
  VALUE new_object = rb_tracearg_object((rb_trace_arg_t *)tracearg);

  // To keep things fast and practical, we only care about objects that extend
  // either Object or Struct.
  enum ruby_value_type type = rb_type(new_object);
  if (type != RUBY_T_OBJECT && type != RUBY_T_STRUCT) {
    return;
  }

  VALUE klass = rb_class_of(new_object);
  if (klass == Qnil || klass == 0) {
    return;
  }

  struct dd_cov_data *dd_cov_data = RTYPEDDATA_DATA(self);

  if (dd_cov_data->last_allocated_klass == klass) {
    return;
  }

  uintptr_t klass_ptr = (uintptr_t)klass;
  size_t cache_index =
      ((klass_ptr >> 4) ^ (klass_ptr >> 12)) &
      (SEEN_ALLOCATED_CLASS_CACHE_SIZE - 1);
  if (dd_cov_data->seen_allocated_klasses[cache_index] == klass) {
    dd_cov_data->last_allocated_klass = klass;
    return;
  }

  // A direct-cache collision must not make us repeat name resolution or table
  // insertion for a class that this test already observed.
  if (st_is_member(dd_cov_data->klasses_table, (st_data_t)klass)) {
    dd_cov_data->last_allocated_klass = klass;
    dd_cov_data->seen_allocated_klasses[cache_index] = klass;
    return;
  }

  // rb_mod_name returns nil for anonymous classes and is safe during NEWOBJ.
  if (rb_mod_name(klass) == Qnil) {
    return;
  }

  // We use VALUE directly as a key for the hashmap
  // Ruby itself does it too:
  // https://github.com/ruby/ruby/blob/94b87084a689a3bc732dcaee744508a708223d6c/ext/objspace/object_tracing.c#L113
  st_insert(dd_cov_data->klasses_table, (st_data_t)klass, 1);
  dd_cov_data->last_allocated_klass = klass;
  dd_cov_data->seen_allocated_klasses[cache_index] = klass;
}

// DDCov instance methods available in Ruby
static VALUE dd_cov_initialize(int argc, VALUE *argv, VALUE self) {
  VALUE opt;

  rb_scan_args(argc, argv, "10", &opt);
  Check_Type(opt, T_HASH);

  VALUE rb_root = rb_hash_lookup(opt, ID2SYM(rb_intern("root")));
  if (!RTEST(rb_root)) {
    rb_raise(rb_eArgError, "root is required");
  }
  Check_Type(rb_root, T_STRING);
  const char *root = StringValueCStr(rb_root);

  VALUE rb_ignored_path =
      rb_hash_lookup(opt, ID2SYM(rb_intern("ignored_path")));
  const char *ignored_path = NULL;
  if (RTEST(rb_ignored_path)) {
    Check_Type(rb_ignored_path, T_STRING);
    ignored_path = StringValueCStr(rb_ignored_path);
  }

  VALUE rb_threading_mode =
      rb_hash_lookup(opt, ID2SYM(rb_intern("threading_mode")));
  enum threading_mode threading_mode;
  if (rb_threading_mode == ID2SYM(rb_intern("multi"))) {
    threading_mode = multi;
  } else if (rb_threading_mode == ID2SYM(rb_intern("single"))) {
    threading_mode = single;
  } else {
    rb_raise(rb_eArgError, "threading mode is invalid");
  }

  VALUE rb_allocation_tracing_enabled =
      rb_hash_lookup(opt, ID2SYM(rb_intern("use_allocation_tracing")));
  if (rb_allocation_tracing_enabled == Qtrue && threading_mode == single) {
    rb_raise(rb_eArgError,
             "allocation tracing is not supported in single threaded mode");
  }

  struct dd_cov_data *dd_cov_data;
  TypedData_Get_Struct(self, struct dd_cov_data, &dd_cov_data_type,
                       dd_cov_data);

  dd_cov_data->threading_mode = threading_mode;
  dd_cov_data->root_len = RSTRING_LEN(rb_root);
  dd_cov_data->root = dd_ci_ruby_strndup(root, dd_cov_data->root_len);

  if (RTEST(rb_ignored_path)) {
    dd_cov_data->ignored_path_len = RSTRING_LEN(rb_ignored_path);
    dd_cov_data->ignored_path = dd_ci_ruby_strndup(
        ignored_path, dd_cov_data->ignored_path_len);
  }

  if (rb_allocation_tracing_enabled == Qtrue) {
    dd_cov_data->allocation_tracing_enabled = true;
  }

  return Qnil;
}

// starts test impact collection, executed before the start of each test
static VALUE dd_cov_start(VALUE self) {
  struct dd_cov_data *dd_cov_data;
  TypedData_Get_Struct(self, struct dd_cov_data, &dd_cov_data_type,
                       dd_cov_data);

  if (dd_cov_data->root_len == 0) {
    rb_raise(rb_eRuntimeError, "root is required");
  }

  if (active_collector == self) {
    return self;
  }
  if (active_collector != Qnil) {
    rb_raise(rb_eRuntimeError,
             "only one DDCov collector can be active at a time");
  }
  active_collector = self;

  // add line tracepoint
  if (dd_cov_data->threading_mode == single) {
    VALUE thval = rb_thread_current();
    rb_thread_add_event_hook(thval, on_line_event, RUBY_EVENT_LINE, self);
    dd_cov_data->th_covered = thval;
  } else {
    rb_add_event_hook(on_line_event, RUBY_EVENT_LINE, self);
  }

  // Register the same raw hook that TracePoint would wrap, but dispatch
  // directly to the allocation callback. NEWOBJ permits no general Ruby API;
  // the callback is limited to the existing event-safe accessors plus the
  // explicitly safe rb_mod_name lookup.
  if (dd_cov_data->allocation_tracing_enabled &&
      !dd_cov_data->allocation_hook_active) {
    rb_add_event_hook2((rb_event_hook_func_t)on_newobj_event,
                       RUBY_INTERNAL_EVENT_NEWOBJ, self,
                       RUBY_EVENT_HOOK_FLAG_SAFE |
                           RUBY_EVENT_HOOK_FLAG_RAW_ARG);
    dd_cov_data->allocation_hook_active = true;
  }

  return self;
}

// stops test impact collection, executed after the end of each test
// returns the hash with impacted files and resets the internal state
static VALUE dd_cov_stop(VALUE self) {
  struct dd_cov_data *dd_cov_data;
  TypedData_Get_Struct(self, struct dd_cov_data, &dd_cov_data_type,
                       dd_cov_data);

  if (active_collector != self) {
    VALUE inactive_result = dd_cov_data->impacted_files;
    dd_cov_data->impacted_files = rb_hash_new();
    return inactive_result;
  }

  // stop line tracepoint
  if (dd_cov_data->threading_mode == single) {
    VALUE thval = rb_thread_current();
    if (!rb_equal(thval, dd_cov_data->th_covered)) {
      rb_raise(rb_eRuntimeError, "Coverage was not started by this thread");
    }

    rb_thread_remove_event_hook(dd_cov_data->th_covered, on_line_event);
    dd_cov_data->th_covered = Qnil;
  } else {
    rb_remove_event_hook(on_line_event);
  }

  // There is exactly one active collector, so this removes the process's only
  // allocation hook.
  if (dd_cov_data->allocation_hook_active) {
    rb_remove_event_hook_with_data((rb_event_hook_func_t)on_newobj_event, self);
    dd_cov_data->allocation_hook_active = false;
  }

  // process classes covered by allocation tracing
  st_foreach(dd_cov_data->klasses_table, each_instantiated_klass,
             (st_data_t)dd_cov_data);
  dd_cov_data->last_allocated_klass = Qnil;
  memset(dd_cov_data->seen_allocated_klasses, 0,
         sizeof(dd_cov_data->seen_allocated_klasses));
  st_clear(dd_cov_data->klasses_table);

  VALUE res = dd_cov_data->impacted_files;

  dd_cov_data->impacted_files = rb_hash_new();
  dd_cov_data->last_filename = Qnil;
  for (size_t i = 0; i < SEEN_FILENAME_CACHE_SIZE; i++) {
    dd_cov_data->seen_filenames[i] = Qnil;
  }

  active_collector = Qnil;

  return res;
}

void Init_datadog_cov(void) {
  VALUE mDatadog = rb_define_module("Datadog");
  VALUE mCI = rb_define_module_under(mDatadog, "CI");
  VALUE mTestImpactAnalysis = rb_define_module_under(mCI, "TestImpactAnalysis");
  VALUE mCoverage = rb_define_module_under(mTestImpactAnalysis, "Coverage");
  VALUE cDatadogCov = rb_define_class_under(mCoverage, "DDCov", rb_cObject);

  rb_global_variable(&active_collector);

  rb_define_alloc_func(cDatadogCov, dd_cov_allocate);

  rb_define_method(cDatadogCov, "initialize", dd_cov_initialize, -1);
  rb_define_method(cDatadogCov, "start", dd_cov_start, 0);
  rb_define_method(cDatadogCov, "stop", dd_cov_stop, 0);
  rb_define_singleton_method(cDatadogCov, "pack_coverage_files",
                             dd_cov_pack_coverage_files, 3);
}
