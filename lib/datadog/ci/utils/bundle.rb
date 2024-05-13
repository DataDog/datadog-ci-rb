# frozen_string_literal: true

require_relative "../ext/environment"
require_relative "../git/local_repository"

module Datadog
  module CI
    module Utils
      module Bundle
        def self.location
          require "bundler"
          bundle_path = Bundler.bundle_path.to_s
          bundle_path if bundle_path&.start_with?(Datadog::CI::Git::LocalRepository.root)
        rescue => e
          Datadog.logger.warn("Failed to find bundled gems location: #{e}")

          Ext::Environment::POSSIBLE_BUNDLE_LOCATIONS.each do |location|
            path = File.join(Datadog::CI::Git::LocalRepository.root, location)
            return path if File.directory?(path)
          end
          nil
        end
      end
    end
  end
end
