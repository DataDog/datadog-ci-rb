#include <ruby.h>

#include "ruby_internal.h"

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
