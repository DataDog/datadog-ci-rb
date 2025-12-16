#include "datadog_cov.h"
#include "datadog_source_code.h"
#include "datadog_static_dependencies.h"

void Init_datadog_ci_native(void) {
  // Coverage::DDCov
  Init_datadog_cov();

  // Utils::SourceCode
  Init_datadog_source_code();
  Init_datadog_static_dependencies_map();
}
