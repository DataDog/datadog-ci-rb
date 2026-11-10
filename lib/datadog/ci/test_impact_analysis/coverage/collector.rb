# frozen_string_literal: true

require_relative "ddcov"
require_relative "file_access"

module Datadog
  module CI
    module TestImpactAnalysis
      module Coverage
        # Both sources share the existing test/suite/context coverage lifetime.
        class Collector
          def initialize(root:, ignored_path:, threading_mode:, use_allocation_tracing:)
            @ruby = DDCov.new(root: root, ignored_path: ignored_path,
              threading_mode: threading_mode, use_allocation_tracing: use_allocation_tracing)
            @files = FileAccess.new(root: root, ignored_path: ignored_path, threading_mode: threading_mode)
          end

          def start
            @ruby.start
            @files.start
          rescue => e
            FileAccess.warn_failure(e)
          end

          def stop
            files = @files.stop
            @ruby.stop.merge(files)
          rescue => e
            FileAccess.warn_failure(e)
            files || {}
          end
        end
      end
    end
  end
end
