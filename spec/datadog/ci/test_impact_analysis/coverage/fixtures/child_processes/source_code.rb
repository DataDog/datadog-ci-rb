# frozen_string_literal: true

# Run by child_processes_spec.rb in a covered child process without Bundler, so the bootstrap
# removes all the Datadog constants that loading the native extension created.
require "datadog/ci/source_code/method_inspect"
require "datadog/ci/source_code/static_dependencies"

def answer
  42
end

print [
  Datadog::CI::SourceCode::MethodInspect.last_line(method(:answer)),
  Datadog::CI::SourceCode::ISeqCollector.collect
].inspect
