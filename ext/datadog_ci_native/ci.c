#include "datadog_cov.h"
#include "datadog_method_inspect.h"
#include "iseq_collector.h"

void Init_datadog_ci_native(void) {
  // Coverage::DDCov
  Init_datadog_cov();

  // SourceCode
  Init_datadog_method_inspect();
  Init_iseq_collector();
}
