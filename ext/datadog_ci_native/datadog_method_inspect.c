#include <ruby.h>

#include "ruby_internal.h"

static VALUE last_line_from_iseq(VALUE self, VALUE iseqw) {
  const rb_iseq_t *iseq = rb_iseqw_to_iseq(iseqw);

  int line;
  rb_iseq_code_location(iseq, NULL, NULL, &line, NULL);

  return INT2NUM(line);
}

void Init_datadog_method_inspect(void) {
  VALUE mDatadog = rb_define_module("Datadog");
  VALUE mCI = rb_define_module_under(mDatadog, "CI");
  VALUE mSourceCode = rb_define_module_under(mCI, "SourceCode");
  VALUE mMethodInspect = rb_define_module_under(mSourceCode, "MethodInspect");

  rb_define_singleton_method(mMethodInspect, "_native_last_line_from_iseq",
                             last_line_from_iseq, 1);
}
