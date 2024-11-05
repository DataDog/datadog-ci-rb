# frozen_string_literal: true

require "datadog/core/utils/only_once"
require "datadog/core/telemetry/logger"

module Datadog
  module CI
    module Contrib
      # Common behavior for patcher modules.
      module Patcher
        def self.included(base)
          base.singleton_class.prepend(CommonMethods)
        end

        # Prepended instance methods for all patchers
        module CommonMethods
          attr_accessor \
            :patch_error_result,
            :patch_successful

          def patch_name
            (self.class != Class && self.class != Module) ? self.class.name : name
          end

          def patched?
            patch_only_once.ran?
          end

          def patch
            return unless defined?(super)

            patch_only_once.run do
              super.tap do
                @patch_successful = true
              end
            rescue => e
              on_patch_error(e)
            end
          end

          # Processes patching errors. This default implementation logs the error and reports relevant metrics.
          # @param e [Exception]
          def on_patch_error(e)
            Datadog.logger.error("Failed to apply #{patch_name} patch. Cause: #{e} Location: #{Array(e.backtrace).first}")
            Datadog::Core::Telemetry::Logger.report(e, description: "Failed to apply #{patch_name} patch")

            @patch_error_result = {
              type: e.class.name,
              message: e.message,
              line: Array(e.backtrace).first
            }
          end

          private

          def patch_only_once
            # NOTE: This is not thread-safe
            @patch_only_once ||= Datadog::Core::Utils::OnlyOnce.new
          end
        end
      end
    end
  end
end
