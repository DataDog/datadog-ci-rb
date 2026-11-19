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
            else value
            end
          end
        end

        module ClassMethods
          def options
            parent = respond_to?(:superclass) ? superclass : nil
            inherited = parent.respond_to?(:options) ? parent.options : {}
            inherited.merge(@options || {})
          end

          def option(name, **options, &block)
            definition = Option.new(**options)
            block.call(definition) if block
            @options ||= {}
            @options[name] = definition
            define_method(name) { get_option(name) }
            define_method("#{name}=") { |value| set_option(name, value) }
          end

          def settings(name, &block)
            settings_class = Class.new do
              include Base
            end
            settings_class.class_eval(&block)
            option(name) { |definition| definition.default { settings_class.new(environment: environment) } }
          end
        end

        attr_reader :environment

        def initialize(environment: Configuration.environment)
          @environment = environment
          @values = {}
          @explicit_options = {}
        end

        def get_option(name)
          return @values[name] if @values.key?(name)
          definition = self.class.options.fetch(name)
          value = definition.resolve(self)
          value = instance_exec(value, &definition.setter_block) if definition.setter_block
          @values[name] = value
        end

        def set_option(name, value, explicit: true)
          definition = self.class.options.fetch(name)
          value = instance_exec(value, &definition.setter_block) if definition.setter_block
          @values[name] = value
          @explicit_options[name] = true if explicit
          instance_exec(value, &definition.after_set_block) if definition.after_set_block
          value
        end

        def explicit?(name)
          @explicit_options.key?(name)
        end

        def import_option_if_unset(name, value)
          set_option(name, value, explicit: false) unless explicit?(name)
        end

        def reset!
          @values.clear
          @explicit_options.clear
          self
        end

        def to_h
          self.class.options.each_with_object({}) do |(name, _), values|
            value = get_option(name)
            values[name] = value.is_a?(Base) ? value.to_h : value
          end
        end
      end
    end
  end
end
