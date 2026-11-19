# frozen_string_literal: true

module Datadog
  module CI
    module Utils
      module Container
        def self.container_id
          File.read("/proc/self/cgroup")[/[0-9a-f]{64}/]
        rescue SystemCallError
          nil
        end
      end
    end
  end
end
