# frozen_string_literal: true

# Run by child_processes_spec.rb in a covered child process whose RUBYOPT loads datadog-ci
# through auto instrumentation, after the bootstrap.
require "datadog/ci/source_code/method_inspect"

print [
  defined?(Datadog::CI::TestImpactAnalysis::Coverage::DDCov) &&
    Datadog::CI::TestImpactAnalysis::Coverage::DDCov.method_defined?(:start),
  Datadog::CI::SourceCode::MethodInspect::LAST_LINE_AVAILABLE,
  $LOADED_FEATURES.count { |feature| File.basename(feature).start_with?("datadog_ci_native.") }
].inspect
