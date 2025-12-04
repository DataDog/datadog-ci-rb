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
        CONSTANT_WRITE_NODE_CLASSES = [
          Prism::ConstantWriteNode,
          Prism::ConstantAndWriteNode,
          Prism::ConstantOrWriteNode,
          Prism::ConstantOperatorWriteNode
        ].freeze

        CONSTANT_PATH_WRITE_NODE_CLASSES = [
          Prism::ConstantPathWriteNode,
          Prism::ConstantPathAndWriteNode,
          Prism::ConstantPathOrWriteNode,
          Prism::ConstantPathOperatorWriteNode
        ].freeze

        MODULE_OR_CLASS_NODE_CLASSES = [
          Prism::ModuleNode,
          Prism::ClassNode
        ].freeze

        attr_reader :bundle_location, :constant_definitions,
          :constants_used_by_file, :requires_by_file

        def initialize(bundle_location: nil)
          @root = Git::LocalRepository.root
          @bundle_location = bundle_location

          @constant_definitions = {}
          @constants_used_by_file = Hash.new { |hash, key| hash[key] = Set.new }

          @dependencies_cache = {}
        end

        def load
          return if root.nil? || root.empty?
          return unless Dir.exist?(root)

          each_ruby_file do |absolute_path|
            next unless trackable_file?(absolute_path)

            result = Prism.parse_file(absolute_path)
            next unless result.success?

            process_ast(absolute_path, result.value)
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

        def process_ast(file_path, node)
          return if node.nil?

          walk_ast(node, []) do |event|
            constant_name = event[:full]
            next if constant_name.nil? || constant_name.empty?

            case event[:type]
            when :const
              constants_used_by_file[file_path] << constant_name
            when :const_def
              constant_definitions[constant_name] ||= file_path
            end
          end
        end

        def walk_ast(node, namespace, &block)
          return unless node

          new_namespace = namespace

          if module_or_class_node?(node)
            module_name = qualified_constant_name(extract_constant_path_name(node), namespace)
            if module_name
              block&.call(type: :const_def, full: module_name)
              new_namespace = namespace + [module_name]
            end
          elsif (definition_name = constant_definition_name(node, namespace))
            block&.call(type: :const_def, full: definition_name)
          end

          if constant_reference_node?(node)
            constant_reference_candidates(node.full_name, namespace).each do |candidate|
              block&.call(type: :const, full: candidate)
            end
          end

          node.child_nodes.each do |child|
            next if child.nil?
            next if skip_definition_child?(node, child)

            walk_ast(child, new_namespace, &block)
          end
        end

        def constant_definition_name(node, namespace)
          raw_name =
            if constant_write_node?(node)
              node.respond_to?(:full_name) ? node.full_name : node.name&.to_s
            elsif constant_path_write_node?(node)
              node.target&.full_name
            end

          qualified_constant_name(raw_name, namespace)
        end

        def constant_reference_node?(node)
          node.is_a?(Prism::ConstantReadNode) || node.is_a?(Prism::ConstantPathNode)
        end

        def constant_write_node?(node)
          CONSTANT_WRITE_NODE_CLASSES.any? { |klass| node.is_a?(klass) }
        end

        def constant_path_write_node?(node)
          CONSTANT_PATH_WRITE_NODE_CLASSES.any? { |klass| node.is_a?(klass) }
        end

        def module_or_class_node?(node)
          MODULE_OR_CLASS_NODE_CLASSES.any? { |klass| node.is_a?(klass) }
        end

        def extract_constant_path_name(node)
          constant_path = node.constant_path if node.respond_to?(:constant_path)
          constant_path&.full_name
        end

        def definition_target_node(node)
          if constant_path_write_node?(node)
            node.target
          elsif module_or_class_node?(node)
            node.constant_path
          end
        end

        def skip_definition_child?(node, child)
          target = definition_target_node(node)
          target && child.equal?(target)
        end

        def qualified_constant_name(raw_name, namespace_stack)
          return if raw_name.nil? || raw_name.empty?
          return raw_name if absolute_constant_reference?(raw_name)
          return raw_name if raw_name.include?("::")
          return raw_name if namespace_stack.empty?

          "#{namespace_stack.last}::#{raw_name}"
        end

        def absolute_constant_reference?(name)
          name.start_with?("::")
        end

        def constant_reference_candidates(raw_name, namespace_stack)
          return [] if raw_name.nil? || raw_name.empty?

          if absolute_constant_reference?(raw_name)
            [raw_name]
          else
            candidates = []
            namespace_stack.reverse_each do |scope|
              next if scope.nil? || scope.empty?

              candidates << "#{scope}::#{raw_name}"
            end
            candidates << raw_name
            candidates << "::#{raw_name}"
            candidates.uniq
          end
        end
      end
    end
  end
end
