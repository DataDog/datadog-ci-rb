#include <ruby.h>
#include <ruby/debug.h>
#include <ruby/st.h>

#include <stdbool.h>

// This is a native extension that collects a list of Ruby files that were executed during the test run.
// It is used to optimize the test suite by running only the tests that are affected by the changes.

#define PROFILE_FRAMES_BUFFER_SIZE 1

// threading modes
enum threading_mode
{
  single,
  multi
};

// functions declarations
static void on_newobj_event(VALUE tracepoint_data, void *data);

// utility functions
static char *ruby_strndup(const char *str, size_t size)
{
  char *dup;

  dup = xmalloc(size + 1);
  memcpy(dup, str, size);
  dup[size] = '\0';

  return dup;
}

static VALUE just_return_nil(VALUE _not_used_self, VALUE _not_used_exception)
{
  return Qnil;
}

// Equivalent to Ruby "begin/rescue nil" call, where we call a C function and
// swallow the exception if it occurs - const_source_location often fails with
// exceptions for classes that are defined in C or for anonymous classes.
static VALUE rescue_nil(VALUE (*function_to_call_safely)(VALUE), VALUE function_to_call_safely_arg)
{
  return rb_rescue2(
      function_to_call_safely,
      function_to_call_safely_arg,
      just_return_nil,
      Qnil,
      rb_eException, // rb_eException is the base class of all Ruby exceptions
      0              // Required by API to be the last argument
  );
}

static int mark_key_for_gc_i(st_data_t key, st_data_t _value, st_data_t _data)
{
  VALUE klass = (VALUE)key;
  rb_gc_mark(klass);
  return ST_CONTINUE;
}

// Data structure
struct dd_cov_data
{
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

  // Line tracepoint optimisation: cache last seen filename pointer to avoid
  // unnecessary string comparison if we stay in the same file.
  uintptr_t last_filename_ptr;

  // Line tracepoint can work in two modes: single threaded and multi threaded
  //
  // In single threaded mode line tracepoint will only cover the thread that started the coverage.
  // This mode is useful for testing frameworks that run tests in multiple threads.
  // Do not use single threaded mode for Rails applications unless you know that you
  // don't run any background threads.
  //
  // In multi threaded mode line tracepoint will cover all threads. This mode is enabled by default
  // and is recommended for most applications.
  enum threading_mode threading_mode;
  // for single threaded mode: thread that is being covered
  VALUE th_covered;

  // Allocation tracing is used to track test impact for objects that do not
  // contain any methods that could be covered by line tracepoint.
  //
  // Allocation tracing works only in multi threaded mode.
  bool allocation_tracing_enabled;
  VALUE object_allocation_tracepoint;
  st_table *klasses_table; // { (VALUE) -> int } hashmap with class names that were covered by allocation during the test run
};

static void dd_cov_mark(void *ptr)
{
  struct dd_cov_data *dd_cov_data = ptr;
  rb_gc_mark_movable(dd_cov_data->impacted_files);
  rb_gc_mark_movable(dd_cov_data->th_covered);
  rb_gc_mark_movable(dd_cov_data->object_allocation_tracepoint);
  st_foreach(dd_cov_data->klasses_table, mark_key_for_gc_i, 0);
}

static void dd_cov_free(void *ptr)
{
  struct dd_cov_data *dd_cov_data = ptr;
  xfree(dd_cov_data->root);
  xfree(dd_cov_data->ignored_path);
  st_free_table(dd_cov_data->klasses_table);
  xfree(dd_cov_data);
}

static void dd_cov_compact(void *ptr)
{
  struct dd_cov_data *dd_cov_data = ptr;
  dd_cov_data->impacted_files = rb_gc_location(dd_cov_data->impacted_files);
  dd_cov_data->th_covered = rb_gc_location(dd_cov_data->th_covered);
  dd_cov_data->object_allocation_tracepoint = rb_gc_location(dd_cov_data->object_allocation_tracepoint);
}

static const rb_data_type_t dd_cov_data_type = {
    .wrap_struct_name = "dd_cov",
    .function = {
        .dmark = dd_cov_mark,
        .dfree = dd_cov_free,
        .dsize = NULL,
        .dcompact = dd_cov_compact},
    .flags = RUBY_TYPED_FREE_IMMEDIATELY};

static VALUE dd_cov_allocate(VALUE klass)
{
  struct dd_cov_data *dd_cov_data;
  VALUE dd_cov = TypedData_Make_Struct(klass, struct dd_cov_data, &dd_cov_data_type, dd_cov_data);

  dd_cov_data->impacted_files = Qnil;
  dd_cov_data->root = NULL;
  dd_cov_data->root_len = 0;
  dd_cov_data->ignored_path = NULL;
  dd_cov_data->ignored_path_len = 0;
  dd_cov_data->last_filename_ptr = 0;
  dd_cov_data->threading_mode = multi;

  dd_cov_data->allocation_tracing_enabled = true;
  dd_cov_data->object_allocation_tracepoint = Qnil;
  dd_cov_data->klasses_table = st_init_numtable();

  return dd_cov;
}

// Helper functions (available in C only)

// Checks if the filename is located under the root folder of the project (but not
// in the ignored folder) and adds it to the impacted_files hash.
static void record_impacted_file(struct dd_cov_data *dd_cov_data, VALUE filename)
{
  char *filename_ptr = RSTRING_PTR(filename);
  // if the current filename is not located under the root, we skip it
  if (strncmp(dd_cov_data->root, filename_ptr, dd_cov_data->root_len) != 0)
  {
    return;
  }

  // if ignored_path is provided and the current filename is located under the ignored_path, we skip it too
  // this is useful for ignoring bundled gems location
  if (dd_cov_data->ignored_path_len != 0 && strncmp(dd_cov_data->ignored_path, filename_ptr, dd_cov_data->ignored_path_len) == 0)
  {
    return;
  }

  rb_hash_aset(dd_cov_data->impacted_files, filename, Qtrue);
}

// Executed on RUBY_EVENT_LINE event and captures the filename from rb_profile_frames.
static void on_line_event(rb_event_flag_t event, VALUE data, VALUE self, ID id, VALUE klass)
{
  struct dd_cov_data *dd_cov_data;
  TypedData_Get_Struct(data, struct dd_cov_data, &dd_cov_data_type, dd_cov_data);

  const char *c_filename = rb_sourcefile();

  // skip if we cover the same file again
  uintptr_t current_filename_ptr = (uintptr_t)c_filename;
  if (dd_cov_data->last_filename_ptr == current_filename_ptr)
  {
    return;
  }
  dd_cov_data->last_filename_ptr = current_filename_ptr;

  VALUE top_frame;
  int captured_frames = rb_profile_frames(
      0 /* stack starting depth */,
      PROFILE_FRAMES_BUFFER_SIZE,
      &top_frame,
      NULL);

  if (captured_frames != PROFILE_FRAMES_BUFFER_SIZE)
  {
    return;
  }

  VALUE filename = rb_profile_frame_path(top_frame);
  if (filename == Qnil)
  {
    return;
  }

  record_impacted_file(dd_cov_data, filename);
}

// Get source location for a given class name
static VALUE get_source_location(VALUE klass_name)
{
  return rb_funcall(rb_cObject, rb_intern("const_source_location"), 1, klass_name);
}

// Get source location for a given class name and swallow any exceptions
static VALUE safely_get_source_location(VALUE klass_name)
{
  return rescue_nil(get_source_location, klass_name);
}

// This function is called for each class that was instantiated during the test run.
static int process_instantiated_klass(st_data_t key, st_data_t _value, st_data_t data)
{
  VALUE klass = (VALUE)key;
  struct dd_cov_data *dd_cov_data = (struct dd_cov_data *)data;

  VALUE klass_name = rb_class_name(klass);
  if (klass_name == Qnil)
  {
    return ST_CONTINUE;
  }

  VALUE source_location = safely_get_source_location(klass_name);
  if (source_location == Qnil || RARRAY_LEN(source_location) == 0)
  {
    return ST_CONTINUE;
  }

  VALUE filename = RARRAY_AREF(source_location, 0);
  if (filename == Qnil)
  {
    return ST_CONTINUE;
  }

  record_impacted_file(dd_cov_data, filename);
  return ST_CONTINUE;
}

// Executed on RUBY_INTERNAL_EVENT_NEWOBJ event and captures the source file for the
// allocated object's class.
static void on_newobj_event(VALUE tracepoint_data, void *data)
{
  VALUE self = (VALUE)data;
  struct dd_cov_data *dd_cov_data;
  TypedData_Get_Struct(self, struct dd_cov_data, &dd_cov_data_type, dd_cov_data);

  rb_trace_arg_t *tracearg = rb_tracearg_from_tracepoint(tracepoint_data);
  VALUE new_object = rb_tracearg_object(tracearg);

  // To keep things fast and practical, we only care about objects that extend
  // either Object or Struct.
  enum ruby_value_type type = rb_type(new_object);
  if (type != RUBY_T_OBJECT && type != RUBY_T_STRUCT)
  {
    return;
  }

  VALUE klass = rb_class_of(new_object);
  if (klass == Qnil || klass == 0)
  {
    return;
  }
  // Skip anonymous classes starting with "#<Class".
  // it allows us to skip the source location lookup that will always fail
  const char *name = rb_obj_classname(new_object);
  const unsigned long klass_name_len = strlen(name);
  if (klass_name_len >= 2 && name[0] == '#' && name[1] == '<')
  {
    return;
  }

  // We use VALUE directly as a key for the hashmap
  // Ruby itself does it too:
  // https://github.com/ruby/ruby/blob/94b87084a689a3bc732dcaee744508a708223d6c/ext/objspace/object_tracing.c#L113
  if (st_lookup(dd_cov_data->klasses_table, (st_data_t)klass, 0))
  {
    return;
  }

  st_insert(dd_cov_data->klasses_table, (st_data_t)klass, 1);
}

// DDCov instance methods available in Ruby
static VALUE dd_cov_initialize(int argc, VALUE *argv, VALUE self)
{
  VALUE opt;

  rb_scan_args(argc, argv, "10", &opt);
  VALUE rb_root = rb_hash_lookup(opt, ID2SYM(rb_intern("root")));
  if (!RTEST(rb_root))
  {
    rb_raise(rb_eArgError, "root is required");
  }
  VALUE rb_ignored_path = rb_hash_lookup(opt, ID2SYM(rb_intern("ignored_path")));

  VALUE rb_threading_mode = rb_hash_lookup(opt, ID2SYM(rb_intern("threading_mode")));
  enum threading_mode threading_mode;
  if (rb_threading_mode == ID2SYM(rb_intern("multi")))
  {
    threading_mode = multi;
  }
  else if (rb_threading_mode == ID2SYM(rb_intern("single")))
  {
    threading_mode = single;
  }
  else
  {
    rb_raise(rb_eArgError, "threading mode is invalid");
  }

  VALUE rb_allocation_tracing_enabled = rb_hash_lookup(opt, ID2SYM(rb_intern("use_allocation_tracing")));
  if (rb_allocation_tracing_enabled == Qtrue && threading_mode == single)
  {
    rb_raise(rb_eArgError, "allocation tracing is not supported in single threaded mode");
  }

  struct dd_cov_data *dd_cov_data;
  TypedData_Get_Struct(self, struct dd_cov_data, &dd_cov_data_type, dd_cov_data);

  dd_cov_data->impacted_files = rb_hash_new();
  dd_cov_data->threading_mode = threading_mode;
  dd_cov_data->root_len = RSTRING_LEN(rb_root);
  dd_cov_data->root = ruby_strndup(RSTRING_PTR(rb_root), dd_cov_data->root_len);

  if (RTEST(rb_ignored_path))
  {
    dd_cov_data->ignored_path_len = RSTRING_LEN(rb_ignored_path);
    dd_cov_data->ignored_path = ruby_strndup(RSTRING_PTR(rb_ignored_path), dd_cov_data->ignored_path_len);
  }

  dd_cov_data->allocation_tracing_enabled = (rb_allocation_tracing_enabled == Qtrue);
  dd_cov_data->object_allocation_tracepoint = rb_tracepoint_new(Qnil, RUBY_INTERNAL_EVENT_NEWOBJ, on_newobj_event, (void *)self);

  return Qnil;
}

// starts test impact collection, executed before the start of each test
static VALUE dd_cov_start(VALUE self)
{
  struct dd_cov_data *dd_cov_data;
  TypedData_Get_Struct(self, struct dd_cov_data, &dd_cov_data_type, dd_cov_data);

  if (dd_cov_data->root_len == 0)
  {
    rb_raise(rb_eRuntimeError, "root is required");
  }

  // add line tracepoint
  if (dd_cov_data->threading_mode == single)
  {
    VALUE thval = rb_thread_current();
    rb_thread_add_event_hook(thval, on_line_event, RUBY_EVENT_LINE, self);
    dd_cov_data->th_covered = thval;
  }
  else
  {
    rb_add_event_hook(on_line_event, RUBY_EVENT_LINE, self);
  }

  // add object allocation tracepoint
  if (dd_cov_data->allocation_tracing_enabled)
  {
    rb_tracepoint_enable(dd_cov_data->object_allocation_tracepoint);
  }

  return self;
}

// stops test impact collection, executed after the end of each test
// returns the hash with impacted files and resets the internal state
static VALUE dd_cov_stop(VALUE self)
{
  struct dd_cov_data *dd_cov_data;
  TypedData_Get_Struct(self, struct dd_cov_data, &dd_cov_data_type, dd_cov_data);

  // stop line tracepoint
  if (dd_cov_data->threading_mode == single)
  {
    VALUE thval = rb_thread_current();
    if (!rb_equal(thval, dd_cov_data->th_covered))
    {
      rb_raise(rb_eRuntimeError, "Coverage was not started by this thread");
    }

    rb_thread_remove_event_hook(dd_cov_data->th_covered, on_line_event);
    dd_cov_data->th_covered = Qnil;
  }
  else
  {
    rb_remove_event_hook(on_line_event);
  }

  // stop object allocation tracepoint
  if (dd_cov_data->object_allocation_tracepoint != Qnil)
  {
    rb_tracepoint_disable(dd_cov_data->object_allocation_tracepoint);
  }

  // process classes covered by allocation tracing
  st_foreach(dd_cov_data->klasses_table, process_instantiated_klass, (st_data_t)dd_cov_data);
  st_clear(dd_cov_data->klasses_table);

  VALUE res = dd_cov_data->impacted_files;

  dd_cov_data->impacted_files = rb_hash_new();
  dd_cov_data->last_filename_ptr = 0;

  return res;
}

void Init_datadog_cov(void)
{
  VALUE mDatadog = rb_define_module("Datadog");
  VALUE mCI = rb_define_module_under(mDatadog, "CI");
  VALUE mTestOptimisation = rb_define_module_under(mCI, "TestOptimisation");
  VALUE mCoverage = rb_define_module_under(mTestOptimisation, "Coverage");
  VALUE cDatadogCov = rb_define_class_under(mCoverage, "DDCov", rb_cObject);

  rb_define_alloc_func(cDatadogCov, dd_cov_allocate);

  rb_define_method(cDatadogCov, "initialize", dd_cov_initialize, -1);
  rb_define_method(cDatadogCov, "start", dd_cov_start, 0);
  rb_define_method(cDatadogCov, "stop", dd_cov_stop, 0);
}
