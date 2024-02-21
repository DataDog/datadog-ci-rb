# frozen_string_literal: true

require "coverage"
require "rotoscope"
require "set"

require_relative "../../utils/git"

module Datadog
  module CI
    module Itr
      module Coverage
        class Collector
          def initialize
            @coverage_supported = true
            # @coverage_supported = false

            @regex = /\A#{Regexp.escape(Utils::Git.root + File::SEPARATOR)}/i.freeze
          end

          def setup
          end

          def start
            @results = {}

            @rs = Rotoscope.new do |call|
              if call.caller_path =~ @regex
                @results[call.caller_path] ||= Set.new
                @results[call.caller_path] << call.caller_lineno
              end
            end
            @rs.start_trace
          end

          def stop
            @rs.stop_trace

            @results
          end
        end
      end
    end
  end
end
