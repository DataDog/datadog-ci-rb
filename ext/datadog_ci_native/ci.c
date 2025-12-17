#include "datadog_cov.h"
#include "datadog_method_inspect.h"
#include "datadog_static_dependencies.h"

void Init_datadog_ci_native(void) {
  // Coverage::DDCov
  Init_datadog_cov();

  // SourceCode
  Init_datadog_method_inspect();
  Init_datadog_static_dependencies_map();
}
