# frozen_string_literal: true

require "set"

require_relative "../../utils/git"

module Datadog
  module CI
    module Itr
      module Coverage
        class Collector
          def initialize(mode: :files, enabled: true)
            # modes available: :files, :lines
            @mode = mode
            @enabled = enabled
            @regex = /\A#{Regexp.escape(Utils::Git.root + File::SEPARATOR)}/i.freeze

            @coverage = {}

            if @enabled
              @tracepoint = TracePoint.new(:line) do |tp|
                next unless tp.path =~ @regex

                if @mode == :files
                  @coverage[tp.path] = true
                elsif @mode == :lines
                  @coverage[tp.path] ||= Set.new
                  @coverage[tp.path] << tp.lineno
                end
              end
            end
          end

          def setup
            if @enabled
              p "RUNNING WITH CODE COVERAGE ENABLED AND MODE #{@mode}"
            else
              p "RUNNING WITH CODE COVERAGE DISABLED"
            end
          end

          def start
            return unless @enabled

            @tracepoint.enable
          end

          def stop
            return unless @enabled
            @tracepoint.disable
            res = @coverage
            @coverage = {}
            res
          end
        end
      end
    end
  end
end
