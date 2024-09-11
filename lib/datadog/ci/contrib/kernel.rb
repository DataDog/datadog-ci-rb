module Datadog
  module CI
    module Contrib
      class Instance
        def initialize
          @on_require = {}
          @integrations = {}
        end

        def require(path)
          Datadog.logger.debug { "Path: #{path}" }
          @on_require.keys.each do |script_name|
            if path.include?(script_name) && @integrations[script_name].class.loaded?
              Datadog.logger.debug { "Gem '#{script_name}' loaded. Configuring integration." }

              Contrib.disable_trace_requires
              @on_require[script_name].call
            end
          end
        rescue => e
          Datadog.logger.debug do
            "Failed to execute callback for gem: #{e.class.name} #{e.message} at #{Array(e.backtrace).join("\n")}"
          end
        end

        def on_require(gem, &block)
          @on_require[gem] = block
        end

        def register(gem, integration)
          @integrations[gem] = integration
        end
      end

      @@dd_instance = Instance.new

      def self.on_require(gem, &block)
        @@dd_instance.on_require(gem, &block)
      end

      def self.register(gem, integration)
        @@dd_instance.register(gem, integration)
      end

      def self.enable_trace_requires
        @@trp = TracePoint.new(:script_compiled) do |tp|
          @@dd_instance.require(tp.instruction_sequence.path)
        end

        @@trp.enable
      end

      def self.disable_trace_requires
        @@trp.disable
      end
    end
  end
end
