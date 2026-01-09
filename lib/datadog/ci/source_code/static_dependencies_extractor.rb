# frozen_string_literal: true

require_relative "path_filter"
require_relative "constant_resolver"

module Datadog
  module CI
    module SourceCode
      # StaticDependenciesExtractor extracts static constant dependencies from Ruby bytecode.
      #
      # For each ISeq (compiled Ruby code), it:
      # 1. Extracts the source file path
      # 2. Filters by root_path and ignored_path
      # 3. Scans bytecode for constant references
      # 4. Resolves constants to their source file locations
      # 5. Filters dependency paths by root_path and ignored_path
      #
      # @example
      #   extractor = StaticDependenciesExtractor.new("/app", "/app/vendor")
      #   iseq = RubyVM::InstructionSequence.of(some_method)
      #   extractor.extract(iseq)
      #   deps = extractor.dependencies_map
      #   # => { "/app/foo.rb" => { "/app/bar.rb" => true } }
      #
      class StaticDependenciesExtractor
        # BytecodeScanner scans Ruby bytecode instructions for constant references.
        #
        # This class traverses the ISeq#to_a representation to find:
        # - :getconstant instructions - simple constant references
        # - :opt_getconstant_path instructions - optimized qualified constant paths
        #
        # @api private
        class BytecodeScanner
          # Scan an ISeq body for constant references.
          #
          # @param body [Array] The ISeq body array (last element of ISeq#to_a)
          # @return [Array<String>] Array of constant name strings found in the bytecode
          def scan(body)
            return [] unless body.is_a?(Array)

            constants = []
            scan_value(body, constants)
            constants
          end

          # Build a qualified constant name from an array of symbols.
          # e.g., [:Foo, :Bar, :Baz] -> "Foo::Bar::Baz"
          #
          # @param symbol_array [Array<Symbol>] Array of constant name symbols
          # @return [String] The qualified constant path string
          def build_constant_path(symbol_array)
            symbol_array
              .select { |part| part.is_a?(Symbol) }
              .map(&:to_s)
              .join("::")
          end

          private

          # Recursively scan a Ruby value for constant references.
          #
          # @param value [Object] Any Ruby value from the ISeq representation
          # @param constants [Array<String>] Accumulator for found constants
          def scan_value(value, constants)
            case value
            when Array
              scan_array(value, constants)
            when Hash
              scan_hash(value, constants)
            end
          end

          # Scan an array for instructions and nested values.
          #
          # @param arr [Array] Array to scan
          # @param constants [Array<String>] Accumulator for found constants
          def scan_array(arr, constants)
            handle_instruction(arr, constants)

            arr.each do |elem|
              scan_value(elem, constants)
            end
          end

          # Scan a hash for constant references in keys and values.
          #
          # @param hash [Hash] Hash to scan
          # @param constants [Array<String>] Accumulator for found constants
          def scan_hash(hash, constants)
            hash.each do |key, val|
              scan_value(key, constants)
              scan_value(val, constants)
            end
          end

          # Check if an array is a bytecode instruction and handle it.
          # Instructions have the form [:instruction_name, ...args].
          #
          # @param arr [Array] Potential instruction array
          # @param constants [Array<String>] Accumulator for found constants
          def handle_instruction(arr, constants)
            return if arr.size < 2
            return unless arr[0].is_a?(Symbol)

            case arr[0]
            when :getconstant
              handle_getconstant(arr, constants)
            when :opt_getconstant_path
              handle_opt_getconstant_path(arr, constants)
            end
          end

          # Handle [:getconstant, :CONST_NAME, ...] instruction.
          #
          # @param instruction [Array] The instruction array
          # @param constants [Array<String>] Accumulator for found constants
          def handle_getconstant(instruction, constants)
            const_name = instruction[1]
            return unless const_name.is_a?(Symbol)

            constants << const_name.to_s
          end

          # Handle [:opt_getconstant_path, cache_entry] instruction.
          # The cache entry is an array of symbols: [:Foo, :Bar, :Baz]
          #
          # @param instruction [Array] The instruction array
          # @param constants [Array<String>] Accumulator for found constants
          def handle_opt_getconstant_path(instruction, constants)
            cache_entry = instruction[1]
            return unless cache_entry.is_a?(Array) && !cache_entry.empty?

            path = build_constant_path(cache_entry)
            constants << path unless path.empty?
          end
        end

        # @return [Hash{String => Hash{String => Boolean}}] Map of source file to dependencies
        attr_reader :dependencies_map

        # @return [String] Root path prefix for filtering
        attr_reader :root_path

        # @return [String, nil] Ignored path prefix for exclusion
        attr_reader :ignored_path

        # Initialize a new StaticDependenciesExtractor.
        #
        # @param root_path [String] Only process files under this path
        # @param ignored_path [String, nil] Exclude files under this path
        def initialize(root_path, ignored_path = nil)
          @root_path = root_path
          @ignored_path = ignored_path
          @dependencies_map = {}
          @bytecode_scanner = BytecodeScanner.new
        end

        # Extract constant dependencies from an ISeq.
        #
        # @param iseq [RubyVM::InstructionSequence] The instruction sequence to process
        # @return [void]
        def extract(iseq)
          path = extract_absolute_path(iseq)
          return if path.nil?
          return unless PathFilter.included?(path, root_path, ignored_path)

          body = extract_body(iseq)
          return if body.nil?

          deps = get_or_create_deps(path)
          constant_names = @bytecode_scanner.scan(body)

          constant_names.each do |const_name|
            resolve_and_store_dependency(const_name, deps)
          end
        end

        # Reset the dependencies map.
        #
        # @return [void]
        def reset
          @dependencies_map = {}
        end

        private

        # Extract the absolute path from an ISeq.
        # Returns nil for eval'd code (which has no file).
        #
        # @param iseq [RubyVM::InstructionSequence]
        # @return [String, nil]
        def extract_absolute_path(iseq)
          path = iseq.absolute_path
          return nil unless path.is_a?(String)

          path
        end

        # Extract the body array from an ISeq's SimpleDataFormat.
        # The body is the last element of ISeq#to_a.
        #
        # @param iseq [RubyVM::InstructionSequence]
        # @return [Array, nil]
        def extract_body(iseq)
          arr = iseq.to_a
          return nil unless arr.is_a?(Array) && !arr.empty?

          body = arr[-1]
          return nil unless body.is_a?(Array)

          body
        end

        # Get or create dependencies hash for a given path.
        #
        # @param path [String]
        # @return [Hash{String => Boolean}]
        def get_or_create_deps(path)
          @dependencies_map[path] ||= {}
        end

        # Resolve a constant name to its file and store in dependencies.
        #
        # @param constant_name [String]
        # @param deps [Hash{String => Boolean}]
        # @return [void]
        def resolve_and_store_dependency(constant_name, deps)
          file_path = ConstantResolver.resolve_path(constant_name)
          return if file_path.nil?
          return unless PathFilter.included?(file_path, root_path, ignored_path)

          deps[file_path] = true
        end
      end
    end
  end
end
