# frozen_string_literal: true

module Datadog
  module CI
    module Contrib
      module Instrumentation
        class InvalidIntegrationError < StandardError; end

        @registry = {}

        def self.registry
          @registry
        end

        def self.register_integration(integration_class)
          @registry[integration_name(integration_class)] = integration_class.new
        end

        # Manual instrumentation of a specific integration.
        #
        # This method is called when user has `c.ci.instrument :integration_name` in their code.
        def self.instrument(integration_name, options = {}, &block)
          integration = fetch_integration(integration_name)
          integration.configure(options, &block)

          return unless integration.enabled

          patch_results = integration.patch
          if patch_results == true
            # try to patch dependant integrations (for example knapsack that depends on rspec)
            dependants = integration.dependants
              .map { |name| fetch_integration(name) }
              .filter { |integration| integration.patchable? }

            Datadog.logger.debug("Found dependent integrations for #{integration_name}: #{dependants}")

            dependants.each do |dependent_integration|
              dependent_integration.patch
            end
          else
            error_message = <<-ERROR
                  Available?: #{patch_results[:available]}, Loaded?: #{patch_results[:loaded]},
                  Compatible?: #{patch_results[:compatible]}, Patchable?: #{patch_results[:patchable]}"
            ERROR
            Datadog.logger.warn("Unable to patch #{integration_name} (#{error_message})")
          end
        end

        # This method instruments all additional test libraries (ex: selenium-webdriver) that need to be instrumented
        # later in the test suite run.
        #
        # It is intended to be called when test session starts to add additional capabilities to test visibility.
        #
        # This method does not automatically instrument test frameworks (ex: RSpec, Cucumber, etc), it requires
        # test framework to be already instrumented.
        def self.instrument_on_session_start
          Datadog.logger.debug("Instrumenting all late instrumented integrations...")

          @registry.each do |name, integration|
            next unless integration.late_instrument?

            Datadog.logger.debug "#{name} is allowed to be late instrumented"

            patch_results = integration.patch
            if patch_results == true
              Datadog.logger.debug("#{name} is patched")
            else
              Datadog.logger.debug("#{name} is not patched (#{patch_results})")
            end
          end
        end

        def self.fetch_integration(name)
          @registry[name] ||
            raise(InvalidIntegrationError, "'#{name}' is not a valid integration.")
        end

        # take the parent module name and downcase it
        # for example for Datadog::CI::Contrib::RSpec::Integration it will be :rspec
        def self.integration_name(subclass)
          result = subclass.name&.split("::")&.[](-2)&.downcase&.to_sym
          raise "Integration name could not be derived for #{subclass}" if result.nil?
          result
        end
      end
    end
  end
end
