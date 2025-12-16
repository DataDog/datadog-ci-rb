#include "imemo_helpers.h"
#include "ruby_internal.h"

int dd_imemo_type(VALUE imemo) {
  return (RBASIC(imemo)->flags >> FL_USHIFT) & DD_IMEMO_MASK;
}

bool dd_imemo_iseq_p(VALUE v) {
  if (!rb_objspace_internal_object_p(v))
    return false;
  if (!RB_TYPE_P(v, T_IMEMO))
    return false;
  if (dd_imemo_type(v) != DD_IMEMO_TYPE_ISEQ)
    return false;
  return true;
}
