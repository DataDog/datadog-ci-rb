# frozen_string_literal: true

require "set"
require "prism"

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
          @bundle_location = bundle_location

          @constants_defined_by_file = Hash.new { |hash, key| hash[key] = Set.new }
          @constants_used_by_file = Hash.new { |hash, key| hash[key] = Set.new }
          @requires_by_file = Hash.new { |hash, key| hash[key] = Set.new }

          @dependencies_cache = {}
        end

        def load
          return if root.nil? || root.empty?
          return unless Dir.exist?(root)

          each_ruby_file do |absolute_path|
            next unless trackable_file?(absolute_path)

            result = Prism.parse_file(absolute_path)
            next unless result.success?

            result.value
          rescue => e
            Datadog.logger.warn { "DependenciesTracker failed to parse #{absolute_path}: #{e.class} - #{e.message}" }
          end
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

          path != bundle_location && !path.start_with?("#{bundle_location}#{File::SEPARATOR}")
        end

        def each_ruby_file(&block)
          Dir.glob(File.join(root, "**", "*.rb")).each(&block)
        end
      end
    end
  end
end
