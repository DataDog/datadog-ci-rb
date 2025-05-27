#include <ruby.h>

// These structs and functions are not exported by MRI because they are part of
// the internal API. We declare them here to use them via dynamic linking.
typedef struct rb_iseq_struct rb_iseq_t;
const rb_iseq_t *rb_iseqw_to_iseq(VALUE iseqw);
void rb_iseq_code_location(const rb_iseq_t *, int *first_lineno,
                           int *first_column, int *last_lineno,
                           int *last_column);

static VALUE last_line_from_iseq(VALUE self, VALUE iseqw) {
  const rb_iseq_t *iseq = rb_iseqw_to_iseq(iseqw);

  int line;
  rb_iseq_code_location(iseq, NULL, NULL, &line, NULL);

  return INT2NUM(line);
}

void Init_datadog_source_code(void) {
  VALUE mDatadog = rb_define_module("Datadog");
  VALUE mCI = rb_define_module_under(mDatadog, "CI");
  VALUE mUtils = rb_define_module_under(mCI, "Utils");
  VALUE mSourceCode = rb_define_module_under(mUtils, "SourceCode");

  rb_define_singleton_method(mSourceCode, "_native_last_line_from_iseq",
                             last_line_from_iseq, 1);
}
