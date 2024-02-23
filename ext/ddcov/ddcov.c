#include <ruby.h>
#include <ruby/debug.h>
#include <stdio.h>

// Utils
static bool prefix(const char *pre, const char *str)
{
  return strncmp(pre, str, strlen(pre)) == 0;
}

// Data structure
struct dd_cov_data
{
  char *root;
  VALUE coverage;
};

static void dd_cov_mark(void *ptr)
{
  // printf("MARK\n");
  struct dd_cov_data *dd_cov_data = ptr;
  rb_gc_mark_movable(dd_cov_data->coverage);
}

static void dd_cov_free(void *ptr)
{
  // printf("FREE\n");
  struct dd_cov_data *dd_cov_data = ptr;

  xfree(dd_cov_data);
}

static void dd_cov_compact(void *ptr)
{
  // printf("COMPACT\n");
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
  // printf("ALLOCATE\n");
  struct dd_cov_data *dd_cov_data;
  VALUE obj = TypedData_Make_Struct(klass, struct dd_cov_data, &dd_cov_data_type, dd_cov_data);
  dd_cov_data->coverage = rb_hash_new();
  return obj;
}

// DDCov methods
static VALUE dd_cov_initialize(VALUE self, VALUE rb_root)
{
  // printf("INITIALIZE\n");
  struct dd_cov_data *dd_cov_data;
  TypedData_Get_Struct(self, struct dd_cov_data, &dd_cov_data_type, dd_cov_data);

  // printf("struct got\n");
  dd_cov_data->root = StringValueCStr(rb_root);
  // printf("root set\n");

  return Qnil;
}

static void dd_cov_update_line_coverage(rb_event_flag_t event, VALUE data, VALUE self, ID id, VALUE klass)
{
  // printf("EVENT HOOK FIRED\n");
  // printf("FILE: %s\n", rb_sourcefile());
  // printf("LINE: %d\n", rb_sourceline());
  struct dd_cov_data *dd_cov_data;
  TypedData_Get_Struct(data, struct dd_cov_data, &dd_cov_data_type, dd_cov_data);

  const char *filename = rb_sourcefile();
  if (filename == 0)
  {
    return;
  }

  if (!prefix(dd_cov_data->root, filename))
  {
    return;
  }

  unsigned long len_filename = strlen(filename);

  VALUE rb_str_source_file = rb_str_new(filename, len_filename);
  rb_hash_aset(dd_cov_data->coverage, rb_str_source_file, Qtrue);
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
  // remove event hook
  rb_thread_remove_event_hook(thval, dd_cov_update_line_coverage);

  struct dd_cov_data *dd_cov_data;
  TypedData_Get_Struct(self, struct dd_cov_data, &dd_cov_data_type, dd_cov_data);

  VALUE cov = dd_cov_data->coverage;

  dd_cov_data->coverage = rb_hash_new();

  return cov;
}

void Init_ddcov(void)
{
  VALUE cDDCov = rb_define_class("DDCov", rb_cObject);

  rb_define_alloc_func(cDDCov, dd_cov_allocate);

  rb_define_method(cDDCov, "initialize", dd_cov_initialize, 1);
  rb_define_method(cDDCov, "start", dd_cov_start, 0);
  rb_define_method(cDDCov, "stop", dd_cov_stop, 0);
}
