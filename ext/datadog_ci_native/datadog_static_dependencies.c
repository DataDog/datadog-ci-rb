#include <ruby.h>
#include <stdbool.h>

#include "datadog_common.h"
#include "imemo_helpers.h"
#include "ruby_internal.h"

/* ---- Static IDs --------------------------------------------------------- */
static ID id_getconstant;
static ID id_opt_getconstant_path;
static ID id_keys;
static ID id_to_a;
static ID id_absolute_path;
static ID id_ivar_deps_map;

/* ---- Context for ISeq walking ------------------------------------------- */
struct populate_data {
  VALUE deps_map;
  const char *root_path;
  long root_path_len;
  const char *ignored_path;
  long ignored_path_len;
};

/* ---- Path filtering ----------------------------------------------------- */

/* Check if a file path is under root_path and not under ignored_path */
static bool is_path_included(const char *file_path_ptr,
                             struct populate_data *pd) {
  if (strncmp(pd->root_path, file_path_ptr, pd->root_path_len) != 0) {
    return false;
  }
  if (pd->ignored_path_len > 0 &&
      strncmp(pd->ignored_path, file_path_ptr, pd->ignored_path_len) == 0) {
    return false;
  }
  return true;
}

/* ---- Constant resolution helpers ---------------------------------------- */

/*
 * Resolve a constant name to its source file and store in deps_hash
 * if the file is within the allowed paths.
 */
static void resolve_and_store_constant(VALUE const_name_str, VALUE deps_hash,
                                       struct populate_data *pd) {
  VALUE file_path = dd_ci_resolve_const_to_file(const_name_str);
  if (NIL_P(file_path)) {
    return;
  }
  if (!is_path_included(RSTRING_PTR(file_path), pd)) {
    return;
  }
  rb_hash_aset(deps_hash, file_path, Qtrue);
}

/*
 * Build a qualified constant name "Foo::Bar::Baz" from an array of symbols.
 * Returns an empty string if no valid symbols found.
 */
static VALUE build_constant_path_string(VALUE symbol_array) {
  long path_len = RARRAY_LEN(symbol_array);
  VALUE result = rb_str_new_cstr("");

  for (long i = 0; i < path_len; i++) {
    VALUE part = rb_ary_entry(symbol_array, i);
    if (!SYMBOL_P(part)) {
      continue;
    }
    if (RSTRING_LEN(result) > 0) {
      rb_str_cat_cstr(result, "::");
    }
    rb_str_append(result, rb_sym2str(part));
  }
  return result;
}

/* ---- Instruction handlers ----------------------------------------------- */

/*
 * Handle [:getconstant, :CONST, ...] instruction.
 * Resolves the constant symbol to its source file location.
 */
static void handle_getconstant(VALUE instruction, VALUE deps_hash,
                               struct populate_data *pd) {
  VALUE const_name = rb_ary_entry(instruction, 1);
  if (!SYMBOL_P(const_name)) {
    return;
  }
  VALUE const_name_str = rb_sym2str(const_name);
  resolve_and_store_constant(const_name_str, deps_hash, pd);
}

/*
 * Handle [:opt_getconstant_path, <cache_entry>] instruction.
 * The cache entry is an array of symbols representing the constant path,
 * e.g., [:Foo, :Bar, :Baz] -> "Foo::Bar::Baz"
 */
static void handle_opt_getconstant_path(VALUE instruction, VALUE deps_hash,
                                        struct populate_data *pd) {
  VALUE cache_entry = rb_ary_entry(instruction, 1);
  if (!RB_TYPE_P(cache_entry, T_ARRAY) || RARRAY_LEN(cache_entry) == 0) {
    return;
  }
  VALUE const_name_str = build_constant_path_string(cache_entry);
  if (RSTRING_LEN(const_name_str) == 0) {
    return;
  }
  resolve_and_store_constant(const_name_str, deps_hash, pd);
}

/* ---- ISeq body scanning ------------------------------------------------- */

/* Forward declaration for recursive scanning */
static void scan_value_for_constants(VALUE obj, VALUE deps_hash,
                                     struct populate_data *pd);

/*
 * Check if an array looks like a bytecode instruction and handle it.
 * Instructions have the form [:instruction_name, ...args].
 */
static void try_handle_instruction(VALUE arr, VALUE deps_hash,
                                   struct populate_data *pd) {
  if (RARRAY_LEN(arr) < 2) {
    return;
  }
  VALUE first = rb_ary_entry(arr, 0);
  if (!SYMBOL_P(first)) {
    return;
  }

  ID instruction_id = rb_sym2id(first);
  if (instruction_id == id_getconstant) {
    handle_getconstant(arr, deps_hash, pd);
  } else if (instruction_id == id_opt_getconstant_path) {
    handle_opt_getconstant_path(arr, deps_hash, pd);
  }
}

static void scan_array_for_constants(VALUE arr, VALUE deps_hash,
                                     struct populate_data *pd) {
  try_handle_instruction(arr, deps_hash, pd);

  long len = RARRAY_LEN(arr);
  for (long i = 0; i < len; i++) {
    VALUE elem = rb_ary_entry(arr, i);
    scan_value_for_constants(elem, deps_hash, pd);
  }
}

static void scan_hash_for_constants(VALUE hash, VALUE deps_hash,
                                    struct populate_data *pd) {
  VALUE keys = rb_funcall(hash, id_keys, 0);
  long len = RARRAY_LEN(keys);

  for (long i = 0; i < len; i++) {
    VALUE key = rb_ary_entry(keys, i);
    VALUE val = rb_hash_aref(hash, key);
    scan_value_for_constants(key, deps_hash, pd);
    scan_value_for_constants(val, deps_hash, pd);
  }
}

/*
 * Recursively scan a Ruby value (from ISeq#to_a) for constant references.
 * Handles arrays (including bytecode instructions) and hashes.
 */
static void scan_value_for_constants(VALUE obj, VALUE deps_hash,
                                     struct populate_data *pd) {
  switch (TYPE(obj)) {
  case T_ARRAY:
    scan_array_for_constants(obj, deps_hash, pd);
    break;
  case T_HASH:
    scan_hash_for_constants(obj, deps_hash, pd);
    break;
  default:
    break;
  }
}

/* ---- ISeq processing ---------------------------------------------------- */

/*
 * Get the absolute path from an ISeq, returning Qnil if invalid.
 * Only real files have absolute paths (eval'd code returns nil).
 */
static VALUE get_iseq_absolute_path(VALUE iseq) {
  VALUE path = rb_funcall(iseq, id_absolute_path, 0);
  if (NIL_P(path) || !RB_TYPE_P(path, T_STRING)) {
    return Qnil;
  }
  return path;
}

/*
 * Extract the body array from an ISeq's SimpleDataFormat representation.
 * Returns Qnil if the format is unexpected.
 *
 * ISeq#to_a format:
 * ["YARVInstructionSequence/SimpleDataFormat", major, minor, fmt_type,
 *  misc, label, path, absolute_path, first_lineno, type, locals, args,
 *  catch_table, body]
 */
static VALUE get_iseq_body(VALUE iseq) {
  // Here we convert the iseq to a Ruby array that is somewhat suboptimal
  // and requires some objects to be allocated on Ruby heap.
  //
  // But it gives us the following advantages:
  // - we don't have to support all the different internal iseq representations
  // that differ for different Ruby versions
  // - the code to iterate and inspect the iseqs will be a lot simpler
  VALUE arr = rb_funcall(iseq, id_to_a, 0);
  if (!RB_TYPE_P(arr, T_ARRAY) || RARRAY_LEN(arr) <= 0) {
    return Qnil;
  }
  VALUE body = rb_ary_entry(arr, RARRAY_LEN(arr) - 1);
  if (!RB_TYPE_P(body, T_ARRAY)) {
    return Qnil;
  }
  return body;
}

/*
 * Get or create the dependencies hash for a given file path.
 */
static VALUE get_or_create_deps_for_path(VALUE deps_map, VALUE path) {
  VALUE deps = rb_hash_aref(deps_map, path);
  if (NIL_P(deps)) {
    deps = rb_hash_new();
    rb_hash_aset(deps_map, path, deps);
  }
  return deps;
}

/*
 * Process a single ISeq: extract its path, filter by root/ignored paths,
 * then scan its bytecode body for constant references.
 */
static void process_iseq(VALUE iseq, struct populate_data *pd) {
  VALUE path = get_iseq_absolute_path(iseq);
  if (NIL_P(path)) {
    return;
  }
  if (!is_path_included(RSTRING_PTR(path), pd)) {
    return;
  }

  VALUE body = get_iseq_body(iseq);
  if (NIL_P(body)) {
    return;
  }

  VALUE deps = get_or_create_deps_for_path(pd->deps_map, path);

  // here we start graph traversing to inspect the bytecode
  scan_value_for_constants(body, deps, pd);
}

/* ---- Object space iteration --------------------------------------------- */

/*
 * Callback for rb_objspace_each_objects.
 *
 * The callback receives a range of object slots [vstart, vend) with given
 * stride. Each slot may contain a live object, a freed slot, or garbage.
 * We check each slot for ISeq objects and process them.
 *
 * See:
 * https://github.com/ruby/ruby/blob/c99670d6683fec770271d35c2ae082514b1abce3/gc.c#L3550
 */
static int os_each_iseq_cb(void *vstart, void *vend, size_t stride,
                           void *data) {
  struct populate_data *pd = (struct populate_data *)data;

  for (VALUE v = (VALUE)vstart; v != (VALUE)vend; v += stride) {
    if (dd_ci_imemo_iseq_p(v)) {
      VALUE iseq = rb_iseqw_new((void *)v);
      process_iseq(iseq, pd);
    }
  }
  return 0;
}

/* ---- initialize the temp C struct that we use to pass data to the callback -
 */

static void init_populate_data(struct populate_data *pd, VALUE deps_map,
                               VALUE rb_root_path, VALUE rb_ignored_path) {
  pd->deps_map = deps_map;
  pd->root_path = RSTRING_PTR(rb_root_path);
  pd->root_path_len = RSTRING_LEN(rb_root_path);

  pd->ignored_path = NULL;
  pd->ignored_path_len = 0;
  if (rb_ignored_path != Qnil && RB_TYPE_P(rb_ignored_path, T_STRING) &&
      RSTRING_LEN(rb_ignored_path) > 0) {
    pd->ignored_path = RSTRING_PTR(rb_ignored_path);
    pd->ignored_path_len = RSTRING_LEN(rb_ignored_path);
  }
}

/* ---- Public API --------------------------------------------------------- */

/*
 * StaticDependencies.populate!(root_path, ignored_path)
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
 *   might be GC'd). Method ISeqs usually survive.
 * - eval'd ISeqs (absolute_path == nil) are ignored.
 * - Constants defined in C extensions will not have source locations.
 */
static VALUE iseq_const_usage_populate(VALUE self, VALUE rb_root_path,
                                       VALUE rb_ignored_path) {
  if (NIL_P(rb_root_path) || !RB_TYPE_P(rb_root_path, T_STRING)) {
    rb_raise(rb_eArgError, "root_path must be a String and not nil");
  }

  // initialize the dependencies map
  VALUE deps_map = rb_hash_new();
  rb_ivar_set(self, id_ivar_deps_map, deps_map);

  struct populate_data pd;
  init_populate_data(&pd, deps_map, rb_root_path, rb_ignored_path);

  rb_objspace_each_objects(os_each_iseq_cb, &pd);

  return deps_map;
}

/* ---- Module initialization ---------------------------------------------- */

void Init_datadog_static_dependencies_map(void) {
  VALUE mDatadog = rb_define_module("Datadog");
  VALUE mCI = rb_define_module_under(mDatadog, "CI");
  VALUE mSourceCode = rb_define_module_under(mCI, "SourceCode");
  VALUE mStaticDependencies =
      rb_define_module_under(mSourceCode, "StaticDependencies");

  id_getconstant = rb_intern("getconstant");
  id_opt_getconstant_path = rb_intern("opt_getconstant_path");
  id_keys = rb_intern("keys");
  id_to_a = rb_intern("to_a");
  id_absolute_path = rb_intern("absolute_path");
  id_ivar_deps_map = rb_intern("@dependencies_map");

  VALUE dependencies_map = rb_hash_new();
  rb_ivar_set(mStaticDependencies, id_ivar_deps_map, dependencies_map);

  rb_define_singleton_method(mStaticDependencies, "populate!",
                             iseq_const_usage_populate, 2);
}
