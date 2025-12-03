# frozen_string_literal: true

require "set"

require_relative "../git/local_repository"

module Datadog
  module CI
    module TestOptimisation
      # Tracks constant dependencies between Ruby files.
      # Subsequent steps will populate and query the tracker,
      # but Step 1 focuses on the class structure and filtering helpers.
      class DependenciesTracker
        attr_reader :bundle_location, :constants_defined_by_file,
          :constants_used_by_file, :requires_by_file

        def initialize(bundle_location: nil)
          @root = Git::LocalRepository.root
          @bundle_location = Git::LocalRepository.relative_to_root(bundle_location)

          @constants_defined_by_file = Hash.new { |hash, key| hash[key] = Set.new }
          @constants_used_by_file = Hash.new { |hash, key| hash[key] = Set.new }
          @requires_by_file = Hash.new { |hash, key| hash[key] = Set.new }

          @dependencies_cache = {}
        end

        def load
          # implemented in later steps
        end

        def fetch_dependencies(_source_path)
          # implemented in later steps
          Set.new
        end

        private

        attr_reader :root, :dependencies_cache

        def trackable_file?(path)
          return false if path.nil? || path.empty?
          return true if bundle_location.nil? || bundle_location.empty?

          !path&.start_with?("#{bundle_location}#{File::SEPARATOR}")
        end
      end
    end
  end
end
