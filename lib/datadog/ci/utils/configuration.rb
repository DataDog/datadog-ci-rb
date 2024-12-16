# frozen_string_literal: true

require_relative "../git/local_repository"

module Datadog
  module CI
    module Utils
      module Configuration
        def self.fetch_service_name(default)
          Datadog.configuration.service_without_fallback || CI::Git::LocalRepository.repository_name || default
        end

        def self.service_name_provided_by_user?
          !!Datadog.configuration.service_without_fallback
        end
      end
    end
  end
end
