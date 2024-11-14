# frozen_string_literal: true

module Datadog
  module CI
    module Contrib
      module Instrumentation
        class InvalidIntegrationError < StandardError; end

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

        def self.fetch_integration(name)
          Datadog::CI::Contrib::Integration.registry[name] ||
            raise(InvalidIntegrationError, "'#{name}' is not a valid integration.")
        end
      end
    end
  end
end
