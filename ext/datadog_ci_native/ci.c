#include "datadog_cov.h"
#include "datadog_method_inspect.h"
#include "file_serialization.h"
#include "file_dependencies.h"
#include "iseq_collector.h"
#include "line_coverage.h"

void Init_datadog_ci_native(void) {
  // Coverage::DDCov
  Init_datadog_cov();

  // FileSerialization
  Init_file_serialization();
  Init_file_dependencies();

  // SourceCode
  Init_datadog_method_inspect();
  Init_dd_ci_iseq_collector();

  // Coverage::LineCollector
  Init_dd_ci_line_coverage();
}
