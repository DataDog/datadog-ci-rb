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
        CACHE_MISS = Object.new.freeze
        private_constant :CACHE_MISS

        # BytecodeScanner scans Ruby bytecode instructions for constant references.
        #
        # This class traverses the ISeq#to_a representation to find:
        # - :getconstant instructions - simple constant references
        # - :opt_getconstant_path instructions - optimized qualified constant paths
        #
        # @api private
        class BytecodeScanner
          ISEQ_FORMAT_HEADER = "YARVInstructionSequence/SimpleDataFormat"
          private_constant :ISEQ_FORMAT_HEADER

          # Scan an ISeq body (or full SimpleDataFormat array) for constant references.
          #
          # @param body [Array] The ISeq body array (last element of ISeq#to_a) or ISeq#to_a
          # @return [Array<String>] Array of constant name strings found in the bytecode
          def scan(body)
            return [] unless body.is_a?(Array)

            constants = []
            # @type var constants: Array[String]
            stack = [body]
            # @type var stack: Array[Array[untyped]]

            while (arr = stack.pop)
              len = arr.size
              next if len == 0

              first = arr[0]
              if first.is_a?(Symbol)
                if len >= 2
                  if first == :getconstant
                    handle_getconstant(arr, constants)
                    next
                  elsif first == :opt_getconstant_path
                    handle_opt_getconstant_path(arr, constants)
                    next
                  end
                else
                  next
                end
                i = 1
              elsif first == ISEQ_FORMAT_HEADER && len >= 14
                catch_table = arr[12]
                iseq_body = arr[13]
                stack << catch_table if catch_table.is_a?(Array) && !catch_table.empty?
                stack << iseq_body if iseq_body.is_a?(Array) && !iseq_body.empty?
                next
              else
                i = 0
              end

              while i < len
                elem = arr[i]
                if elem.is_a?(Array)
                  scan_child_array(elem, stack, constants)
                elsif elem.is_a?(Hash)
                  push_hash_containers(elem, stack)
                end
                i += 1
              end
            end

            constants
          end

          # Build a qualified constant name from an array of symbols.
          # e.g., [:Foo, :Bar, :Baz] -> "Foo::Bar::Baz"
          #
          # @param symbol_array [Array<Symbol>] Array of constant name symbols
          # @return [String] The qualified constant path string
          def build_constant_path(symbol_array)
            size = symbol_array.size
            return "" if size == 0

            if size == 1
              part = symbol_array[0]
              return part.is_a?(Symbol) ? part.to_s : ""
            end

            if symbol_array.all?(Symbol)
              symbol_array.join("::")
            else
              symbol_array
                .select { |part| part.is_a?(Symbol) }
                .join("::")
            end
          end

          private

          def scan_child_array(elem, stack, constants)
            elen = elem.size
            return if elen == 0

            efirst = elem[0]
            if efirst.is_a?(Symbol)
              return if elen < 2

              if efirst == :opt_send_without_block
                # Operand is only a call_data Hash (never contains constant instructions)
                nil
              elsif efirst == :getconstant
                handle_getconstant(elem, constants)
              elsif efirst == :opt_getconstant_path
                handle_opt_getconstant_path(elem, constants)
              elsif efirst == :send || efirst == :invokesuper
                # arr[1] is call_data Hash; only arr[2] (block ISeq) can contain instructions
                blk = elem[2]
                stack << blk if blk.is_a?(Array)
              elsif elen == 2
                operand = elem[1]
                if operand.is_a?(Array)
                  stack << operand
                elsif operand.is_a?(Hash)
                  push_hash_containers(operand, stack)
                end
              else
                stack << elem
              end
            else
              stack << elem
            end
          end

          def push_hash_containers(hash, stack)
            hash.each do |key, val|
              if key.is_a?(Array)
                stack << key
              elsif key.is_a?(Hash)
                push_hash_containers(key, stack)
              end

              if val.is_a?(Array)
                stack << val
              elsif val.is_a?(Hash)
                push_hash_containers(val, stack)
              end
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
          @resolved_constants_cache = {}
        end

        # Extract constant dependencies from an ISeq.
        #
        # @param iseq [RubyVM::InstructionSequence] The instruction sequence to process
        # @return [void]
        def extract(iseq)
          path = extract_absolute_path(iseq)
          return if path.nil?
          return unless PathFilter.included?(path, root_path, ignored_path)

          iseq_array = extract_body(iseq)
          return if iseq_array.nil?

          deps = get_or_create_deps(path)
          constant_names = @bytecode_scanner.scan(iseq_array)

          constant_names.each do |const_name|
            resolve_and_store_dependency(const_name, deps)
          end
        end

        # Reset the dependencies map.
        #
        # @return [void]
        def reset
          @dependencies_map = {}
          @resolved_constants_cache = {}
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

        # Extract the SimpleDataFormat array (or body) from an ISeq.
        # Returning the full SimpleDataFormat array allows BytecodeScanner
        # to scan both catch_table (index 12) and body (index 13).
        #
        # @param iseq [RubyVM::InstructionSequence]
        # @return [Array, nil]
        def extract_body(iseq)
          arr = iseq.to_a
          return nil unless arr.is_a?(Array) && !arr.empty?

          return arr if arr.size >= 14 && arr[13].is_a?(Array)

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
          file_path = @resolved_constants_cache.fetch(constant_name, CACHE_MISS)
          if file_path.equal?(CACHE_MISS)
            resolved = ConstantResolver.resolve_path(constant_name)
            file_path = (resolved && PathFilter.included?(resolved, root_path, ignored_path)) ? resolved : nil
            @resolved_constants_cache[constant_name] = file_path
          end

          deps[file_path] = true if file_path.is_a?(String)
        end
      end
    end
  end
end
