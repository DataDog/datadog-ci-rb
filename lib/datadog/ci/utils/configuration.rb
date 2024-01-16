# frozen_string_literal: true

require_relative "git"

module Datadog
  module CI
    module Utils
      module Configuration
        def self.fetch_service_name(default)
          Datadog.configuration.service_without_fallback || Git.repository_name || default
        end
      end
    end
  end
end
