# frozen_string_literal: true

require "msgpack"

module Datadog
  module CI
    module TestImpactAnalysis
      module Coverage
        # One part of the lines a process executed that are in no test's own lines:
        # "init" (initialiser code), "suiteSetup" (suite fixtures) or "unowned"
        # (everything else). Sent once per process, at exit. It carries the part in place
        # of a span id.
        #
        # @internal
        class SharedEvent
          attr_reader :test_session_id, :part

          def initialize(test_session_id:, part:, files:)
            @test_session_id = test_session_id
            @part = part
            @files = files
          end

          def valid?
            true
          end

          def inspect_coverage
            @files.inspect_coverage
          end

          def to_msgpack(packer = nil)
            packer ||= MessagePack::Packer.new

            packer.write_map_header(3)

            packer.write("test_session_id")
            packer.write(test_session_id.to_i)

            packer.write("shared")
            packer.write(part)

            packer.write("files")
            @files.write_to(packer)
          end

          def to_s
            "Coverage::SharedEvent[test_session_id=#{test_session_id}, part=#{part}, files=#{@files.size}]"
          end
        end
      end
    end
  end
end
