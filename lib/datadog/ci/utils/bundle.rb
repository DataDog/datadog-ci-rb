# frozen_string_literal: true

require_relative "../ext/environment"
require_relative "../git/local_repository"

module Datadog
  module CI
    module Utils
      module Bundle
        def self.location
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
