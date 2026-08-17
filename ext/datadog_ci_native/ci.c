#include "datadog_cov.h"
#include "datadog_method_inspect.h"
#include "file_serialization.h"
#include "iseq_collector.h"

void Init_datadog_ci_native(void) {
  // Coverage::DDCov
  Init_datadog_cov();

  // FileSerialization
  Init_file_serialization();

  // SourceCode
  Init_datadog_method_inspect();
  Init_dd_ci_iseq_collector();
}
