# frozen_string_literal: true

require_relative "../ext/metadata"

module Datadog
  module CI
    module Utils
      module ProtectedTags
        @mutex = Mutex.new
        @reported = {}

        def self.reject?(key, operation)
          return false unless Ext::Metadata::PROTECTED_TAGS.include?(key.to_s)

          report = @mutex.synchronize do
            id = [key.to_s.dup.freeze, operation]
            next false if @reported.key?(id)

            @reported[id] = true
          end
          Datadog.logger.error("Ignoring #{operation} for SDK-owned tag #{key}; use the supported configuration or instrumentation API") if report
          true
        end

        def self.initial_tags(tags)
          tags.reject do |key, _|
            !Ext::Metadata::INITIAL_TAGS.include?(key.to_s) && reject?(key, :initial_tags)
          end
        end
      end
    end
  end
end
