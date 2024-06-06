#include <ruby.h>
#include <ruby/debug.h>

#define PROFILE_FRAMES_BUFFER_SIZE 1

// threading modes
#define SINGLE_THREADED_COVERAGE_MODE 0
#define MULTI_THREADED_COVERAGE_MODE 1

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

  uintptr_t last_filename_ptr;

  int threading_mode;
};

static void dd_cov_mark(void *ptr)
{
  struct dd_cov_data *dd_cov_data = ptr;
  rb_gc_mark_movable(dd_cov_data->coverage);
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
  VALUE obj = TypedData_Make_Struct(klass, struct dd_cov_data, &dd_cov_data_type, dd_cov_data);

  dd_cov_data->coverage = rb_hash_new();
  dd_cov_data->root = NULL;
  dd_cov_data->root_len = 0;
  dd_cov_data->ignored_path = NULL;
  dd_cov_data->ignored_path_len = 0;
  dd_cov_data->last_filename_ptr = 0;
  dd_cov_data->threading_mode = MULTI_THREADED_COVERAGE_MODE;

  return obj;
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
  if (!RTEST(rb_threading_mode) || rb_threading_mode == ID2SYM(rb_intern("multi")))
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

  return Qnil;
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
  }
  else
  {
    rb_add_event_hook(dd_cov_update_coverage, RUBY_EVENT_LINE, self);
  }

  // add event hook
  rb_thread_add_event_hook(thval, dd_cov_update_coverage, RUBY_EVENT_LINE, self);

  return self;
}

static VALUE dd_cov_stop(VALUE self)
{
  struct dd_cov_data *dd_cov_data;
  TypedData_Get_Struct(self, struct dd_cov_data, &dd_cov_data_type, dd_cov_data);

  if (dd_cov_data->threading_mode == SINGLE_THREADED_COVERAGE_MODE)
  {
    VALUE thval = rb_thread_current();
    rb_thread_remove_event_hook(thval, dd_cov_update_coverage);
  }
  else
  {
    rb_remove_event_hook(dd_cov_update_coverage);
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
  VALUE mITR = rb_define_module_under(mCI, "ITR");
  VALUE mCoverage = rb_define_module_under(mITR, "Coverage");
  VALUE cDatadogCov = rb_define_class_under(mCoverage, "DDCov", rb_cObject);

  rb_define_alloc_func(cDatadogCov, dd_cov_allocate);

  rb_define_method(cDatadogCov, "initialize", dd_cov_initialize, -1);
  rb_define_method(cDatadogCov, "start", dd_cov_start, 0);
  rb_define_method(cDatadogCov, "stop", dd_cov_stop, 0);
}
