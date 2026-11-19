# frozen_string_literal: true

module Datadog
  module CI
    module Configuration
      # Defines lazy configuration values without sharing tracer configuration.
      module Base
        def self.included(base)
          base.extend(ClassMethods)
        end

        class Option
          attr_reader :environment_names, :kind, :default_value, :default_block, :setter_block, :after_set_block

          def initialize(default: nil, **_options)
            @default_value = default
            @environment_names = []
          end

          def type(kind, **_options)
            @kind = kind
          end

          def env(*names)
            @environment_names = names.flatten
          end

          def default(value = nil, &block)
            @default_value = value
            @default_block = block
          end

          def setter(&block)
            @setter_block = block
          end

          def after_set(&block)
            @after_set_block = block
          end

          def resolve(context)
            value = environment_names.lazy.map { |name| context.environment[name] }.find { |item| !item.nil? }
            return cast(value) unless value.nil?
            return context.instance_exec(&default_block) if default_block

            case default_value
            when Hash, Array, String then default_value.dup
            else default_value
            end
          end

          def cast(value)
            case kind
            when :bool then value.to_s.downcase == "true" || value.to_s == "1"
            when :int then Integer(value, exception: false) || default_value
            when :float then Float(value, exception: false) || default_value
            when :array then value.to_s.split(",").map(&:strip)
            else value
            end
          end
        end

        module ClassMethods
          def options
            parent = _ = superclass
            inherited = parent.respond_to?(:options) ? parent.options : {}
            inherited.merge(@options || {})
          end

          def option(name, **options, &block)
            definition = Option.new(**options)
            block&.call(definition)
            definitions = (@options ||= {})
            definitions[name] = definition
            define_method(name) do
              # @type self: Base
              get_option(name)
            end
            define_method("#{name}=") do |value|
              # @type self: Base
              set_option(name, value)
            end
          end

          def settings(name, &block)
            settings_class = Class.new do
              include Base
            end
            settings_class.class_eval(&block)
            option(name) do |definition|
              definition.default do
                # @type self: Base
                settings_class.new(environment: environment)
              end
            end
          end
        end

        attr_reader :environment

        def initialize(environment: Configuration.environment)
          @environment = environment
          @values = {}
          @explicit_options = {}
          @implicit_snapshots = {}
        end

        def get_option(name)
          return @values[name] if @values.key?(name)
          definition = self.class.options.fetch(name)
          value = copy_value(definition.resolve(self))
          value = instance_exec(value, &definition.setter_block) if definition.setter_block
          @values[name] = value
          instance_exec(value, &definition.after_set_block) if definition.after_set_block
          remember_implicit_value(name, value)
          value
        end

        def set_option(name, value, explicit: true)
          definition = self.class.options.fetch(name)
          value = instance_exec(value, &definition.setter_block) if definition.setter_block
          @values[name] = value
          @explicit_options[name] = true if explicit
          instance_exec(value, &definition.after_set_block) if definition.after_set_block
          remember_implicit_value(name, value)
          value
        end

        def configure(options = {})
          options.each do |name, value|
            current = get_option(name)
            if current.is_a?(Base) && value.is_a?(Hash)
              current.configure(value)
            else
              set_option(name, value)
            end
          end
          yield self if block_given?
          self
        end

        def explicit?(name)
          return true if @explicit_options.key?(name)
          return false unless @implicit_snapshots.key?(name)
          return false if @values[name] == @implicit_snapshots[name]

          @implicit_snapshots.delete(name)
          @explicit_options[name] = true
        end

        def import_option_if_unset(name, value)
          set_option(name, copy_value(value), explicit: false) unless explicit?(name)
        end

        def reset!
          @values.clear
          @explicit_options.clear
          @implicit_snapshots.clear
          self
        end

        def options
          self.class.options
        end

        def inspect
          "#<#{self.class.name || self.class.superclass&.name}>"
        end

        def to_h
          self.class.options.each_with_object({}) do |(name, _), values|
            value = get_option(name)
            values[name] = value.is_a?(Base) ? value.to_h : value
          end
        end

        private

        def remember_implicit_value(name, value)
          @implicit_snapshots.delete(name)
          return if @explicit_options.key?(name)
          return unless value.is_a?(Hash) || value.is_a?(Array) || value.is_a?(String)

          # Compare copies so that native edits take precedence over later imports.
          @implicit_snapshots[name] = copy_value(value)
        end

        def copy_value(value, copies = {})
          return value unless value.is_a?(Hash) || value.is_a?(Array) || value.is_a?(String)
          return copies[value.object_id] if copies.key?(value.object_id)

          copy = value.dup
          copies[value.object_id] = copy
          if copy.is_a?(Hash)
            copy.each { |key, item| copy[key] = copy_value(item, copies) }
          elsif copy.is_a?(Array)
            copy.map! { |item| copy_value(item, copies) }
          end
          copy
        end
      end
    end
  end
end
