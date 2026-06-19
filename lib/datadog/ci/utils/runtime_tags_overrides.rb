# frozen_string_literal: true

require "json"

require_relative "../ext/test"

module Datadog
  module CI
    module Utils
      module RuntimeTagsOverrides
        TAGS = [
          Ext::Test::TAG_OS_PLATFORM,
          Ext::Test::TAG_OS_ARCHITECTURE,
          Ext::Test::TAG_OS_VERSION,
          Ext::Test::TAG_RUNTIME_NAME,
          Ext::Test::TAG_RUNTIME_VERSION
        ].freeze

        def self.parse(value)
          return {} if value.nil? || value.to_s.strip.empty?

          parsed = JSON.parse(value.to_s)
          unless parsed.is_a?(Hash)
            Datadog.logger.warn("Invalid runtime tag overrides configuration: expected JSON object")
            return {}
          end

          parsed.each_with_object({}) do |(key, tag_value), tags|
            next unless TAGS.include?(key)
            next if tag_value.nil?

            normalized_value = tag_value.to_s.strip
            next if normalized_value.empty?

            tags[key] = normalized_value
          end
        rescue JSON::ParserError => e
          Datadog.logger.warn("Invalid runtime tag overrides configuration: #{e.message}")
          {}
        end
      end
    end
  end
end
