# frozen_string_literal: true

require_relative "integration"

module Datadog
  module CI
    module Contrib
      # This method auto instruments all test libraries (ex: selenium-webdriver).
      # It is intended to be called when test session starts to add additional capabilities to test visibility.
      #
      # This method does not automatically instrument test frameworks (ex: RSpec, Cucumber, etc), it requires
      # test framework to be already instrumented.
      def self.auto_instrument_on_session_start!
        Datadog.logger.debug("Auto instrumenting all integrations...")

        Integration.registry.each do |name, integration|
          next unless integration.auto_instrument?

          Datadog.logger.debug "#{name} is allowed to be auto instrumented"

          patch_results = integration.patch
          if patch_results == true
            Datadog.logger.debug("#{name} is patched")
          else
            Datadog.logger.debug("#{name} is not patched (#{patch_results})")
          end
        end
      end
    end
  end
end
