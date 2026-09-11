# frozen_string_literal: true

require "datadog/tracing/metadata/ext"
require "datadog/tracing/flush"

module Datadog
  module CI
    module Configuration
      # Compatibility layer between Test Optimization and Datadog tracing.
      module TracingCompatibility
        module Flush
          # Adds Test Optimization metadata required by the trace intake.
          module Tagging
            def get_trace(trace_op)
              trace = trace_op.flush!

              trace.spans.each do |span|
                span.set_tag(
                  Tracing::Metadata::Ext::Distributed::TAG_ORIGIN,
                  trace.origin
                )
              end

              trace
            end
          end

          # Consumes only completed traces (where all spans have finished).
          class Finished < Tracing::Flush::Finished
            prepend Tagging
          end

          # Flushes partial traces so large test sessions do not remain in memory.
          class Partial < Tracing::Flush::Partial
            prepend Tagging
          end
        end
      end
    end
  end
end
