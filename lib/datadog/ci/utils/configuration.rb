# frozen_string_literal: true

require_relative "../ext/test"
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

        def self.normalize_tia_test_skipping_mode(mode)
          return mode if Ext::Test::TIATestSkippingMode::ALL.include?(mode)

          Datadog.logger.warn(
            "Invalid Test Impact Analysis skipping mode #{mode.inspect}. " \
            "Falling back to #{Ext::Test::TIATestSkippingMode::TEST.inspect}."
          )

          Ext::Test::TIATestSkippingMode::TEST
        end
      end
    end
  end
end
