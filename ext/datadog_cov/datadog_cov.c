#include <ruby.h>
#include <ruby/debug.h>

#include <stdbool.h>

#define PROFILE_FRAMES_BUFFER_SIZE 1

// threading modes
#define SINGLE_THREADED_COVERAGE_MODE 0
#define MULTI_THREADED_COVERAGE_MODE 1

static void process_newobj_event(VALUE tracepoint_data, void *data);

char *ruby_strndup(const char *str, size_t size)
{
  char *dup;

  dup = xmalloc(size + 1);
  memcpy(dup, str, size);
  dup[size] = '\0';

  return dup;
}

// Data structure
struct dd_cov_data
{
  char *root;
  long root_len;

  char *ignored_path;
  long ignored_path_len;

  VALUE coverage;

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
  int threading_mode;
  // for single threaded mode: thread that is being covered
  VALUE th_covered;

  // Heap allocation tracing is used to track test impact for objects that do not
  // contain any methods that could be covered by line tracepoint.
  //
  // Allocation profiling works only in multi threaded mode.
  bool allocation_profiling_enabled;
  VALUE object_allocation_tracepoint; // Used to get allocation counts and allocation profiling
};

static void dd_cov_mark(void *ptr)
{
  struct dd_cov_data *dd_cov_data = ptr;
  rb_gc_mark_movable(dd_cov_data->coverage);
  rb_gc_mark_movable(dd_cov_data->th_covered);
  rb_gc_mark_movable(dd_cov_data->object_allocation_tracepoint);
}

static void dd_cov_free(void *ptr)
{
  struct dd_cov_data *dd_cov_data = ptr;
  xfree(dd_cov_data->root);
  xfree(dd_cov_data->ignored_path);
  xfree(dd_cov_data);
}

static void dd_cov_compact(void *ptr)
{
  struct dd_cov_data *dd_cov_data = ptr;
  dd_cov_data->coverage = rb_gc_location(dd_cov_data->coverage);
  dd_cov_data->th_covered = rb_gc_location(dd_cov_data->th_covered);
  dd_cov_data->object_allocation_tracepoint = rb_gc_location(dd_cov_data->object_allocation_tracepoint);
}

const rb_data_type_t dd_cov_data_type = {
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

  dd_cov_data->coverage = rb_hash_new();
  dd_cov_data->root = NULL;
  dd_cov_data->root_len = 0;
  dd_cov_data->ignored_path = NULL;
  dd_cov_data->ignored_path_len = 0;
  dd_cov_data->last_filename_ptr = 0;
  dd_cov_data->threading_mode = MULTI_THREADED_COVERAGE_MODE;
  dd_cov_data->allocation_profiling_enabled = true;
  dd_cov_data->object_allocation_tracepoint = rb_tracepoint_new(Qnil, RUBY_INTERNAL_EVENT_NEWOBJ, process_newobj_event, (void *)dd_cov);

  return dd_cov;
}

// DDCov methods
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
  int threading_mode;
  if (rb_threading_mode == ID2SYM(rb_intern("multi")))
  {
    threading_mode = MULTI_THREADED_COVERAGE_MODE;
  }
  else if (rb_threading_mode == ID2SYM(rb_intern("single")))
  {
    threading_mode = SINGLE_THREADED_COVERAGE_MODE;
  }
  else
  {
    rb_raise(rb_eArgError, "threading mode is invalid");
  }

  struct dd_cov_data *dd_cov_data;
  TypedData_Get_Struct(self, struct dd_cov_data, &dd_cov_data_type, dd_cov_data);

  dd_cov_data->threading_mode = threading_mode;
  dd_cov_data->root_len = RSTRING_LEN(rb_root);
  dd_cov_data->root = ruby_strndup(RSTRING_PTR(rb_root), dd_cov_data->root_len);

  if (RTEST(rb_ignored_path))
  {
    dd_cov_data->ignored_path_len = RSTRING_LEN(rb_ignored_path);
    dd_cov_data->ignored_path = ruby_strndup(RSTRING_PTR(rb_ignored_path), dd_cov_data->ignored_path_len);
  }

  dd_cov_data->allocation_profiling_enabled = (threading_mode == MULTI_THREADED_COVERAGE_MODE);

  return Qnil;
}

static void dd_store_covered_filename(struct dd_cov_data *dd_cov_data, VALUE filename)
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

  rb_hash_aset(dd_cov_data->coverage, filename, Qtrue);
}

static void dd_cov_update_coverage(rb_event_flag_t event, VALUE data, VALUE self, ID id, VALUE klass)
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

  dd_store_covered_filename(dd_cov_data, filename);
}

static void process_newobj_event(VALUE tracepoint_data, void *data)
{
  VALUE self = (VALUE)data;
  struct dd_cov_data *dd_cov_data;
  TypedData_Get_Struct(self, struct dd_cov_data, &dd_cov_data_type, dd_cov_data);

  rb_trace_arg_t *tracearg = rb_tracearg_from_tracepoint(tracepoint_data);
  VALUE new_object = rb_tracearg_object(tracearg);

  enum ruby_value_type type = rb_type(new_object);

  if (type != RUBY_T_OBJECT)
  {
    return;
  }

  VALUE klass = rb_class_of(new_object);
  if (klass == Qnil)
  {
    return;
  }

  VALUE klass_name = rb_class_name(klass);
  if (klass_name == Qnil)
  {
    return;
  }

  VALUE rb_module = rb_const_get_at(rb_cObject, rb_intern("Module"));
  VALUE source_location = rb_funcall(rb_module, rb_intern("const_source_location"), 1, klass_name);

  if (source_location == Qnil)
  {
    return;
  }
  VALUE filename = RARRAY_AREF(source_location, 0);

  if (filename == Qnil)
  {
    return;
  }

  dd_store_covered_filename(dd_cov_data, filename);
}

static VALUE dd_cov_start(VALUE self)
{

  struct dd_cov_data *dd_cov_data;
  TypedData_Get_Struct(self, struct dd_cov_data, &dd_cov_data_type, dd_cov_data);

  if (dd_cov_data->root_len == 0)
  {
    rb_raise(rb_eRuntimeError, "root is required");
  }

  if (dd_cov_data->threading_mode == SINGLE_THREADED_COVERAGE_MODE)
  {
    VALUE thval = rb_thread_current();
    rb_thread_add_event_hook(thval, dd_cov_update_coverage, RUBY_EVENT_LINE, self);
    dd_cov_data->th_covered = thval;
  }
  else
  {
    rb_add_event_hook(dd_cov_update_coverage, RUBY_EVENT_LINE, self);
  }

  if (dd_cov_data->allocation_profiling_enabled)
  {
    rb_tracepoint_enable(dd_cov_data->object_allocation_tracepoint);
  }

  return self;
}

static VALUE dd_cov_stop(VALUE self)
{
  struct dd_cov_data *dd_cov_data;
  TypedData_Get_Struct(self, struct dd_cov_data, &dd_cov_data_type, dd_cov_data);

  if (dd_cov_data->threading_mode == SINGLE_THREADED_COVERAGE_MODE)
  {
    VALUE thval = rb_thread_current();
    if (!rb_equal(thval, dd_cov_data->th_covered))
    {
      rb_raise(rb_eRuntimeError, "Coverage was not started by this thread");
    }

    rb_thread_remove_event_hook(dd_cov_data->th_covered, dd_cov_update_coverage);
    dd_cov_data->th_covered = Qnil;
  }
  else
  {
    rb_remove_event_hook(dd_cov_update_coverage);
  }

  if (dd_cov_data->object_allocation_tracepoint != Qnil)
  {
    rb_tracepoint_disable(dd_cov_data->object_allocation_tracepoint);
  }

  VALUE res = dd_cov_data->coverage;

  dd_cov_data->coverage = rb_hash_new();
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
