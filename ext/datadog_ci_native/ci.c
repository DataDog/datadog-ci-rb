#include "datadog_const_usage_map.h"
#include "datadog_cov.h"
#include "datadog_source_code.h"

void Init_datadog_ci_native(void) {
  // Coverage::DDCov
  Init_datadog_cov();

  // Utils::SourceCode
  Init_datadog_source_code();
  Init_datadog_const_usage_map();
}
