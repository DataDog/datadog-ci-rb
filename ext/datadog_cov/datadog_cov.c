#include <ruby.h>
#include <ruby/debug.h>

// constants
#define DD_COV_TARGET_FILES 1
#define DD_COV_TARGET_LINES 2

static int is_prefix(VALUE prefix, const char *str)
{
  if (prefix == Qnil)
  {
    return 0;
  }

  const char *c_prefix = RSTRING_PTR(prefix);
  if (c_prefix == NULL)
  {
    return 0;
  }

  long prefix_len = RSTRING_LEN(prefix);
  if (strncmp(c_prefix, str, prefix_len) == 0)
  {
    return 1;
  }
  else
  {
    return 0;
  }
}

// Data structure
struct dd_cov_data
{
  VALUE root;
  VALUE ignored_path;
  int mode;
  VALUE coverage;
};

static void dd_cov_mark(void *ptr)
{
  struct dd_cov_data *dd_cov_data = ptr;
  rb_gc_mark_movable(dd_cov_data->coverage);
  rb_gc_mark_movable(dd_cov_data->root);
  rb_gc_mark_movable(dd_cov_data->ignored_path);
}

static void dd_cov_free(void *ptr)
{
  struct dd_cov_data *dd_cov_data = ptr;

  xfree(dd_cov_data);
}

static void dd_cov_compact(void *ptr)
{
  struct dd_cov_data *dd_cov_data = ptr;
  dd_cov_data->coverage = rb_gc_location(dd_cov_data->coverage);
  dd_cov_data->root = rb_gc_location(dd_cov_data->root);
  dd_cov_data->ignored_path = rb_gc_location(dd_cov_data->ignored_path);
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
  dd_cov_data->root = Qnil;
  dd_cov_data->ignored_path = Qnil;
  dd_cov_data->mode = DD_COV_TARGET_FILES;
  return obj;
}

// DDCov methods
static VALUE dd_cov_initialize(int argc, VALUE *argv, VALUE self)
{
  VALUE opt;
  int mode;

  rb_scan_args(argc, argv, "10", &opt);
  VALUE rb_root = rb_hash_lookup(opt, ID2SYM(rb_intern("root")));
  if (!RTEST(rb_root))
  {
    rb_raise(rb_eArgError, "root is required");
  }

  VALUE rb_ignored_path = rb_hash_lookup(opt, ID2SYM(rb_intern("ignored_path")));

  VALUE rb_mode = rb_hash_lookup(opt, ID2SYM(rb_intern("mode")));
  if (!RTEST(rb_mode) || rb_mode == ID2SYM(rb_intern("files")))
  {
    mode = DD_COV_TARGET_FILES;
  }
  else if (rb_mode == ID2SYM(rb_intern("lines")))
  {
    mode = DD_COV_TARGET_LINES;
  }
  else
  {
    rb_raise(rb_eArgError, "mode is invalid");
  }

  struct dd_cov_data *dd_cov_data;
  TypedData_Get_Struct(self, struct dd_cov_data, &dd_cov_data_type, dd_cov_data);

  dd_cov_data->root = rb_root;
  dd_cov_data->ignored_path = rb_ignored_path;
  dd_cov_data->mode = mode;

  return Qnil;
}

static void dd_cov_update_line_coverage(rb_event_flag_t event, VALUE data, VALUE self, ID id, VALUE klass)
{
  struct dd_cov_data *dd_cov_data;
  TypedData_Get_Struct(data, struct dd_cov_data, &dd_cov_data_type, dd_cov_data);

  const char *filename = rb_sourcefile();
  if (filename == NULL)
  {
    return;
  }

  // if given filename is not located under the root, we skip it
  if (is_prefix(dd_cov_data->root, filename) == 0)
  {
    return;
  }

  // if ignored_path is provided and given filename is located under the ignored_path, we skip it too
  // this is useful for ignoring bundled gems location
  if (RTEST(dd_cov_data->ignored_path) && is_prefix(dd_cov_data->ignored_path, filename) == 1)
  {
    return;
  }

  VALUE rb_str_source_file = rb_str_new2(filename);

  if (dd_cov_data->mode == DD_COV_TARGET_FILES)
  {
    rb_hash_aset(dd_cov_data->coverage, rb_str_source_file, Qtrue);
    return;
  }

  // this isn't optimized yet, this is a POC to show that lines coverage is possible
  // ITR beta is going to use files coverage, we'll get back to this part when
  // we need to implement lines coverage
  if (dd_cov_data->mode == DD_COV_TARGET_LINES)
  {
    int line_number = rb_sourceline();
    if (line_number <= 0)
    {
      return;
    }

    VALUE rb_lines = rb_hash_aref(dd_cov_data->coverage, rb_str_source_file);
    if (rb_lines == Qnil)
    {
      rb_lines = rb_hash_new();
      rb_hash_aset(dd_cov_data->coverage, rb_str_source_file, rb_lines);
    }

    rb_hash_aset(rb_lines, INT2FIX(line_number), Qtrue);
  }
}

static VALUE dd_cov_start(VALUE self)
{
  // get current thread
  VALUE thval = rb_thread_current();

  // add event hook
  rb_thread_add_event_hook(thval, dd_cov_update_line_coverage, RUBY_EVENT_LINE, self);

  return self;
}

static VALUE dd_cov_stop(VALUE self)
{
  // get current thread
  VALUE thval = rb_thread_current();
  // remove event hook for the current thread
  rb_thread_remove_event_hook(thval, dd_cov_update_line_coverage);

  struct dd_cov_data *dd_cov_data;
  TypedData_Get_Struct(self, struct dd_cov_data, &dd_cov_data_type, dd_cov_data);

  VALUE cov = dd_cov_data->coverage;

  dd_cov_data->coverage = rb_hash_new();

  return cov;
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
