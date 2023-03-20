require "datadog/ci/spec_helper"
require "datadog/ci/contrib/support/mode_helpers"
require "datadog/ci/contrib/support/tracer_helpers"
# require "datadog/tracing/contrib/support/spec_helper"

if defined?(Warning.ignore)
  # Caused by https://github.com/cucumber/cucumber-ruby/blob/47c8e2d7c97beae8541c895a43f9ccb96324f0f1/lib/cucumber/encoding.rb#L5-L6
  Gem.path.each do |path|
    Warning.ignore(/setting Encoding.default_external/, path)
    Warning.ignore(/setting Encoding.default_internal/, path)
  end
end

RSpec.configure do |config|
  config.include Contrib::TracerHelpers

  # Raise error when patching an integration fails.
  # This can be disabled by unstubbing +CommonMethods#on_patch_error+
  require "datadog/tracing/contrib/patcher"
  config.before do
    allow_any_instance_of(Datadog::Tracing::Contrib::Patcher::CommonMethods).to(receive(:on_patch_error)) { |_, e| raise e }
  end

  # Ensure tracer environment is clean before running tests.
  #
  # This is done :before and not :after because doing so after
  # can create noise for test assertions. For example:
  # +expect(Datadog).to receive(:shutdown!).once+
  config.before do
    Datadog.shutdown!
    # without_warnings { Datadog.configuration.reset! }
    Datadog.configuration.reset!
  end
end
