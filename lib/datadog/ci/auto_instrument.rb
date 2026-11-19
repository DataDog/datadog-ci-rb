require "datadog/ci"

if RUBY_ENGINE == "jruby"
  Datadog::CI.logger.error("Auto instrumentation is not supported on JRuby. Please use manual instrumentation instead.")
  return
end

Datadog::CI::Contrib::Instrumentation.auto_instrument
