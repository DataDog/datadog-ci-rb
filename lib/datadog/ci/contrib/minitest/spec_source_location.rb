# frozen_string_literal: true

module Datadog
  module CI
    module Contrib
      module Minitest
        # A spec's test methods may all live in shared helpers. Capture the file
        # that creates the spec while its definition is still on the call stack.
        # This is discovery metadata only, not suite identity or source attribution.
        module SpecSourceLocation
          module ClassMethods
            def inherited(subclass)
              super

              begin
                return unless Datadog.send(:components).test_discovery.enabled?
                return unless defined?(::Minitest::Spec) && ancestors.include?(::Minitest::Spec)

                subclass.dd_spec_source_file = SpecSourceLocation.resolve(caller_locations)
              rescue => e
                Datadog.logger.warn("Could not capture Minitest spec definition: #{e.class}: #{e.message}")
              end
            end
          end

          def self.resolve(locations)
            spec_dsl_file = ::Minitest::Spec::DSL.instance_method(:create).source_location&.first
            # Match Minitest's own describe frame, including aliases of that method.
            # The outermost describe owns nested specs, even when a shared helper
            # creates them. Do not inherit a superclass's file: it may be a helper
            # subclassed by independent specs in several different test files.
            index = locations.rindex { |location| location.path == spec_dsl_file && location.base_label == "describe" }
            location = index ? locations[index + 1] : locations.find { |candidate| candidate.base_label != "inherited" }
            location&.path
          end
        end
      end
    end
  end
end
