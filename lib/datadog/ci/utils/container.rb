# frozen_string_literal: true

module Datadog
  module CI
    module Utils
      module Container
        UUID_PATTERN = "[0-9a-f]{8}[-_]?[0-9a-f]{4}[-_]?[0-9a-f]{4}[-_]?[0-9a-f]{4}[-_]?[0-9a-f]{12}"
        CONTAINER_ID = /\A(?:(?:docker|cri-containerd|crio|libpod)-)?(?<id>[0-9a-f]{64}|#{UUID_PATTERN}|[0-9a-f]{32}-[0-9]{1,10})(?:\.scope)?\z/

        def self.container_id
          File.read("/proc/self/cgroup").b.each_line do |line|
            hierarchy, controllers, path = line.strip.split(":", 3)
            next unless hierarchy&.match?(/\A[0-9]+\z/) && controllers && path&.start_with?("/")

            parts = path.split("/").reject(&:empty?)
            next if parts.length < 2

            # Parent paths can contain task IDs that do not identify the container.
            match = parts.last&.match(CONTAINER_ID)
            return match[:id] if match
          end
          nil
        rescue SystemCallError
          nil
        end
      end
    end
  end
end
