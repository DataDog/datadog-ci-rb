# frozen_string_literal: true

require_relative "../ext/test_optimization_cache"
require_relative "locator"
require_relative "readers/legacy"
require_relative "readers/missing"
require_relative "readers/v1"

module Datadog
  module CI
    module TestOptimizationCache
      class Component
        READER_BY_MANIFEST_VERSION = {
          Ext::TestOptimizationCache::SUPPORTED_MANIFEST_VERSION => Readers::V1
        }.freeze

        def initialize(manifest_file:, runfiles_dir:, runfiles_manifest_file:, test_srcdir:)
          @locator = Locator.new(
            manifest_file: manifest_file,
            runfiles_dir: runfiles_dir,
            runfiles_manifest_file: runfiles_manifest_file,
            test_srcdir: test_srcdir
          )
          @reader = build_reader
        end

        def cache_available?
          @reader.available?
        end

        def load_settings
          @reader.load_settings
        end

        def load_known_tests
          @reader.load_known_tests
        end

        def load_test_management
          @reader.load_test_management
        end

        def load_skippable_tests
          @reader.load_skippable_tests
        end

        def shutdown!
        end

        private

        def build_reader
          manifest_path = @locator.manifest_path

          if manifest_path
            version = @locator.manifest_version(manifest_path)
            reader_class = READER_BY_MANIFEST_VERSION[version] if version
            if reader_class
              test_optimization_path = File.dirname(manifest_path)
              reader = reader_class.new(test_optimization_path)
              return reader if reader.available?

              Datadog.logger.debug do
                "Test Optimization cache settings file not found under #{test_optimization_path}"
              end
              return Readers::Missing.new
            end

            Datadog.logger.debug do
              "Unsupported Test Optimization cache manifest version #{version.inspect} at #{manifest_path}"
            end
            return Readers::Missing.new
          end

          return Readers::Legacy.new if Dir.exist?(Ext::TestOptimizationCache::TESTOPTIMIZATION_CACHE_PATH)

          Readers::Missing.new
        end
      end
    end
  end
end
