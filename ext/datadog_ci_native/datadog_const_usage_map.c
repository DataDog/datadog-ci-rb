#include <ruby.h>
#include <stdbool.h>

/* ---- IDs / ivar names --------------------------------------------------- */
static ID id_getconstant;
static ID id_opt_getconstant_path;
static ID id_keys;
static ID id_to_a;
static ID id_absolute_path;
static ID id_ivar_file_map;
static ID id_const_source_location;

/* ---- Internal MRI functions -------------------- */
/* These are declared in Ruby's internal headers; we just prototype them.   */
/* The linker will resolve them from libruby.                               */

VALUE rb_iseqw_new(const void *iseq); /* wrap internal iseq pointer as
                                         RubyVM::InstructionSequence */
int rb_objspace_internal_object_p(VALUE obj);
void rb_objspace_each_objects(int (*callback)(void *start, void *end,
                                              size_t stride, void *data),
                              void *data);

/* ---- IMEMO constants and helpers ------------------------ */

#define IMEMO_TYPE_ISEQ 7
#define IMEMO_MASK 0x0f

static int imemo_type(VALUE imemo) {
  /* Same bit pattern dd-trace relies on; see their ruby_helpers.c. */
  return (RBASIC(imemo)->flags >> FL_USHIFT) & IMEMO_MASK;
}

static bool imemo_iseq_p(VALUE v) {
  if (!rb_objspace_internal_object_p(v))
    return false;
  if (!RB_TYPE_P(v, T_IMEMO))
    return false;
  if (imemo_type(v) != IMEMO_TYPE_ISEQ)
    return false;
  return true;
}

/* ---- Safe exception handling -------------------------------------------- */

// Equivalent to Ruby "begin/rescue nil" call, where we call a C function and
// swallow the exception if it occurs - const_source_location often fails with
// exceptions for classes that are defined in C or for anonymous classes.
static VALUE rescue_nil(VALUE (*function_to_call_safely)(VALUE),
                        VALUE function_to_call_safely_arg) {
  int exception_state;
  // rb_protect sets exception_state to non-zero if an exception occurs
  VALUE result = rb_protect(function_to_call_safely,
                            function_to_call_safely_arg, &exception_state);
  if (exception_state != 0) {
    rb_set_errinfo(Qnil); // Clear the exception
    return Qnil;
  }
  return result;
}

// Get source location for a given constant name string
static VALUE get_const_source_location(VALUE const_name_str) {
  return rb_funcall(rb_cObject, id_const_source_location, 1, const_name_str);
}

// Get source location for a given constant name and swallow any exceptions
static VALUE safely_get_const_source_location(VALUE const_name_str) {
  return rescue_nil(get_const_source_location, const_name_str);
}

// Resolve constant name to its source file path, returns Qnil if not found
static VALUE resolve_const_to_file(VALUE const_name_str) {
  VALUE source_location = safely_get_const_source_location(const_name_str);
  if (NIL_P(source_location) || !RB_TYPE_P(source_location, T_ARRAY) ||
      RARRAY_LEN(source_location) == 0) {
    return Qnil;
  }

  VALUE filename = RARRAY_AREF(source_location, 0);
  if (NIL_P(filename) || !RB_TYPE_P(filename, T_STRING)) {
    return Qnil;
  }

  return filename;
}

// implementation

struct populate_data {
  VALUE self; /* Module to read @file_to_const_map from (GC-safe) */
  const char *root_path;
  long root_path_len;
  const char *ignored_path;
  long ignored_path_len;
};

/* Forward declaration */
static void scan_value_for_constants(VALUE obj, VALUE const_locations);

static void process_iseq(VALUE iseq, struct populate_data *pd) {
  /* RubyVM::InstructionSequence#absolute_path
     nil for eval'd code; we only care about real files. */
  VALUE path = rb_funcall(iseq, id_absolute_path, 0);
  if (NIL_P(path) || !RB_TYPE_P(path, T_STRING)) {
    return;
  }

  /* Filter: only include files under root_path */
  const char *path_ptr = RSTRING_PTR(path);
  if (strncmp(pd->root_path, path_ptr, pd->root_path_len) != 0) {
    return;
  }

  /* Filter: exclude files under ignored_path */
  if (pd->ignored_path_len > 0 &&
      strncmp(pd->ignored_path, path_ptr, pd->ignored_path_len) == 0) {
    return;
  }

  /* RubyVM::InstructionSequence#to_a (SimpleDataFormat)
     ["YARVInstructionSequence/SimpleDataFormat", major, minor, fmt_type,
      misc, label, path, absolute_path, first_lineno, type, locals, args,
      catch_table, body]
     body is the last element.
  */
  VALUE arr = rb_funcall(iseq, id_to_a, 0);
  if (TYPE(arr) != T_ARRAY)
    return;
  long len = RARRAY_LEN(arr);
  if (len <= 0)
    return;

  VALUE body = rb_ary_entry(arr, len - 1);
  if (TYPE(body) != T_ARRAY)
    return;

  /* Re-read from ivar to get GC-safe reference (compacting GC may move it) */
  VALUE file_to_const_map = rb_ivar_get(pd->self, id_ivar_file_map);

  /* Get or create const_locations hash for this file */
  VALUE const_locations = rb_hash_aref(file_to_const_map, path);
  if (NIL_P(const_locations)) {
    const_locations = rb_hash_new();
    rb_hash_aset(file_to_const_map, path, const_locations);
  }

  /* Scan this ISeq's body for constant references and resolve their
     source locations */
  scan_value_for_constants(body, const_locations);
}

static int os_each_iseq_cb(void *vstart, void *vend, size_t stride,
                           void *data) {
  struct populate_data *pd = (struct populate_data *)data;

  VALUE v = (VALUE)vstart;
  for (; v != (VALUE)vend; v += stride) {
    if (imemo_iseq_p(v)) {
      VALUE iseq = rb_iseqw_new((void *)v);
      process_iseq(iseq, pd);
    }
  }

  return 0;
}

static void scan_value_for_constants(VALUE obj, VALUE const_locations) {
  switch (TYPE(obj)) {
  case T_ARRAY: {
    long len = RARRAY_LEN(obj);

    /* Check instruction forms for constant access */
    if (len >= 2) {
      VALUE first = rb_ary_entry(obj, 0);

      /* Handle [:getconstant, :CONST, ...] */
      if (SYMBOL_P(first) && rb_sym2id(first) == id_getconstant) {
        VALUE const_name = rb_ary_entry(obj, 1);
        if (SYMBOL_P(const_name)) {
          /* Convert symbol to string and resolve location */
          VALUE const_name_str = rb_sym2str(const_name);
          VALUE file_path = resolve_const_to_file(const_name_str);
          if (!NIL_P(file_path)) {
            rb_hash_aset(const_locations, file_path, Qtrue);
          }
        }
      }

      /* Handle [:opt_getconstant_path, <inline_cache>]
         The inline cache contains constant path info; in serialized form
         it may contain an array of symbols representing the constant path. */
      if (SYMBOL_P(first) && rb_sym2id(first) == id_opt_getconstant_path) {
        VALUE cache_entry = rb_ary_entry(obj, 1);
        /* The cache entry in serialized form is typically an array of symbols
           representing the constant path, e.g., [:Foo, :Bar, :Baz] */
        if (TYPE(cache_entry) == T_ARRAY) {
          long path_len = RARRAY_LEN(cache_entry);
          if (path_len > 0) {
            /* Build the full constant path string "Foo::Bar::Baz" */
            VALUE const_name_str = rb_str_new_cstr("");
            for (long j = 0; j < path_len; j++) {
              VALUE part = rb_ary_entry(cache_entry, j);
              if (SYMBOL_P(part)) {
                if (j > 0) {
                  rb_str_cat_cstr(const_name_str, "::");
                }
                rb_str_append(const_name_str, rb_sym2str(part));
              }
            }
            /* Resolve the constant to its source file */
            if (RSTRING_LEN(const_name_str) > 0) {
              VALUE file_path = resolve_const_to_file(const_name_str);
              if (!NIL_P(file_path)) {
                rb_hash_aset(const_locations, file_path, Qtrue);
              }
            }
          }
        }
      }
    }

    /* Recurse into all elements */
    for (long i = 0; i < len; i++) {
      VALUE elem = rb_ary_entry(obj, i);
      scan_value_for_constants(elem, const_locations);
    }
    break;
  }

  case T_HASH: {
    VALUE keys = rb_funcall(obj, id_keys, 0);
    long len = RARRAY_LEN(keys);

    for (long i = 0; i < len; i++) {
      VALUE key = rb_ary_entry(keys, i);
      VALUE val = rb_hash_aref(obj, key);
      scan_value_for_constants(key, const_locations);
      scan_value_for_constants(val, const_locations);
    }
    break;
  }

  default:
    /* Ignore */
    break;
  }
}

/* ---- populate! implementation ------------------------------------------ */
/*
 * ISeqConstUsage.populate!(root_path, ignored_path)
 *
 * Walk all live ISeqs, group by absolute_path, and for each file build
 * a set { file_path(String) => true } of source files where referenced
 * constants are defined. Constants are found via getconstant and
 * opt_getconstant_path instructions in bytecode, then resolved to their
 * source locations using Object.const_source_location.
 *
 * Only files under root_path are included. Files under ignored_path
 * (e.g., bundled gems) are excluded.
 *
 * NOTE:
 * - Only sees code for which ISeqs still exist (top-level file ISeqs
 *   might be GC'd, same as dd-trace's comments in DI PR). Method ISeqs
 *   usually survive, so you still see constants used inside methods.
 * - eval'd ISeqs (absolute_path == nil) are ignored.
 * - Constants defined in C extensions will not have source locations.
 */
static VALUE iseq_const_usage_populate(VALUE self, VALUE rb_root_path,
                                       VALUE rb_ignored_path) {
  /* Validate and extract root_path */
  if (!RB_TYPE_P(rb_root_path, T_STRING)) {
    rb_raise(rb_eArgError, "root_path must be a String");
  }

  /* Setup populate_data struct with all context needed for callback */
  struct populate_data pd;
  pd.self = self; /* Store self to re-read ivar (GC-safe) */
  pd.root_path = RSTRING_PTR(rb_root_path);
  pd.root_path_len = RSTRING_LEN(rb_root_path);

  /* Extract ignored_path (can be nil) */
  pd.ignored_path = NULL;
  pd.ignored_path_len = 0;
  if (RB_TYPE_P(rb_ignored_path, T_STRING)) {
    pd.ignored_path = RSTRING_PTR(rb_ignored_path);
    pd.ignored_path_len = RSTRING_LEN(rb_ignored_path);
  }

  /* Reset map: @file_to_const_map = {} (stored as ivar, GC-rooted) */
  VALUE file_to_const_map = rb_hash_new();
  rb_ivar_set(self, id_ivar_file_map, file_to_const_map);

  /* Walk all live ISeqs and process them directly */
  rb_objspace_each_objects(os_each_iseq_cb, &pd);

  /* Re-read from ivar to return the (possibly moved) VALUE */
  return rb_ivar_get(self, id_ivar_file_map);
}

void Init_datadog_const_usage_map(void) {
  VALUE mDatadog = rb_define_module("Datadog");
  VALUE mCI = rb_define_module_under(mDatadog, "CI");
  VALUE mSourceCode = rb_define_module_under(mCI, "SourceCode");
  VALUE mConstUsage = rb_define_module_under(mSourceCode, "ConstUsage");

  id_getconstant = rb_intern("getconstant");
  id_opt_getconstant_path = rb_intern("opt_getconstant_path");
  id_keys = rb_intern("keys");
  id_to_a = rb_intern("to_a");
  id_absolute_path = rb_intern("absolute_path");
  id_const_source_location = rb_intern("const_source_location");
  id_ivar_file_map = rb_intern("@file_to_const_map");

  /* Initialize @file_to_const_map = {} */
  VALUE file_to_const_map = rb_hash_new();
  rb_ivar_set(mConstUsage, id_ivar_file_map, file_to_const_map);

  /* Ruby APIs */
  rb_define_singleton_method(mConstUsage, "populate!",
                             iseq_const_usage_populate, 2);
}
