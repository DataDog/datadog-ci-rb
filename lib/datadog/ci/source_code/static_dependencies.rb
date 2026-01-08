# frozen_string_literal: true

require_relative "static_dependencies_extractor"

module Datadog
  module CI
    module SourceCode
      # ISeqCollector provides native access to Ruby's object space
      # for collecting instruction sequences (ISeqs).
      #
      # @api private
      module ISeqCollector
        ISEQ_COLLECTOR_AVAILABLE = begin
          # We support Ruby >= 3.2 even though technically it is possible to support 3.1
          # The issue is that Ruby 3.1 and earlier doesn't have opt_getconstant_path YARV instruction
          # which makes it a lot harder to parse fully qualified constant access.
          #
          # See the PR https://github.com/DataDog/datadog-ci-rb/pull/442 for more context
          if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.2")
            require "datadog_ci_native.#{RUBY_VERSION}_#{RUBY_PLATFORM}"
            true
          else
            false
          end
        rescue LoadError
          false
        end

        # Collect all live ISeqs from the Ruby object space.
        # Falls back to empty array if native extension is not available.
        #
        # @return [Array<RubyVM::InstructionSequence>] Array of all live ISeqs
        def self.collect
          return [] unless ISEQ_COLLECTOR_AVAILABLE

          collect_iseqs
        end
      end

      module StaticDependencies
        # Populate the static dependencies map by scanning all live ISeqs.
        #
        # @param root_path [String] Only process files under this path
        # @param ignored_path [String, nil] Exclude files under this path
        # @return [Hash{String => Hash{String => Boolean}}] The dependencies map
        def self.populate!(root_path, ignored_path = nil)
          raise ArgumentError, "root_path must be a String and not nil" if root_path.nil? || !root_path.is_a?(String)

          extractor = StaticDependenciesExtractor.new(root_path, ignored_path)

          ISeqCollector.collect.each do |iseq|
            extractor.extract(iseq)
          end

          @dependencies_map = extractor.dependencies_map
        end

        # Fetch static dependencies for a given file.
        #
        # @param file [String, nil] The file path to look up
        # @return [Hash{String => Boolean}] Dependencies hash or empty hash
        def self.fetch_static_dependencies(file)
          return {} unless @dependencies_map
          return {} if file.nil?

          @dependencies_map.fetch(file, {})
        end
      end
    end
  end
end
