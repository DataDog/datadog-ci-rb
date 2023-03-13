# frozen_string_literal: true

require_relative "ddtrace"
require_relative "ci/version"

require "datadog/core"

module Datadog
  # Namespace for Datadog CI instrumentation:
  # e.g. rspec, cucumber, etc...
  module CI
    class Error < StandardError; end
    # Your code goes here...
  end
end

# Integrations
require_relative "ci/contrib/cucumber/integration"
require_relative "ci/contrib/rspec/integration"

# Extensions
require_relative "ci/extensions"
Datadog::CI::Extensions.activate!
