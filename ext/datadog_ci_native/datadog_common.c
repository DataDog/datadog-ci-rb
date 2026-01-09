#include "datadog_common.h"
#include <ruby.h>
#include <string.h>

bool dd_ci_is_path_included(const char *path, const char *root_path,
                            long root_path_len, const char *ignored_path,
                            long ignored_path_len) {
  if (strncmp(root_path, path, root_path_len) != 0) {
    return false;
  }
  if (ignored_path_len > 0 &&
      strncmp(ignored_path, path, ignored_path_len) == 0) {
    return false;
  }
  return true;
}

char *dd_ci_ruby_strndup(const char *str, size_t size) {
  char *dup;

  dup = xmalloc(size + 1);
  memcpy(dup, str, size);
  dup[size] = '\0';

  return dup;
}

VALUE dd_ci_rescue_nil(VALUE (*function_to_call_safely)(VALUE),
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

VALUE dd_ci_get_const_source_location(VALUE const_name_str) {
  return rb_funcall(rb_cObject, rb_intern("const_source_location"), 1,
                    const_name_str);
}

VALUE dd_ci_safely_get_const_source_location(VALUE const_name_str) {
  return dd_ci_rescue_nil(dd_ci_get_const_source_location, const_name_str);
}

VALUE dd_ci_resolve_const_to_file(VALUE const_name_str) {
  VALUE source_location =
      dd_ci_safely_get_const_source_location(const_name_str);
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
