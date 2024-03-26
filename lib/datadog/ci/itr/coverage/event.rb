# frozen_string_literal: true

require "msgpack"

module Datadog
  module CI
    module ITR
      module Coverage
        class Event
          attr_reader :test_id, :test_suite_id, :test_session_id, :coverage

          def initialize(test_id:, test_suite_id:, test_session_id:, coverage:)
            @test_id = test_id
            @test_suite_id = test_suite_id
            @test_session_id = test_session_id
            @coverage = coverage
          end

          def valid?
            valid = true

            [:test_id, :test_suite_id, :test_session_id, :coverage].each do |key|
              next unless send(key).nil?

              Datadog.logger.warn("citestcov event is invalid: [#{key}] is nil. Event: #{self}")
              valid = false
            end

            valid
          end

          def to_msgpack(packer = nil)
            packer ||= MessagePack::Packer.new

            packer.write_map_header(4)

            packer.write("test_session_id")
            packer.write(test_session_id.to_i)

            packer.write("test_suite_id")
            packer.write(test_suite_id.to_i)

            packer.write("span_id")
            packer.write(test_id.to_i)

            files = coverage.keys
            packer.write("files")
            packer.write_array_header(files.size)

            files.each do |filename|
              packer.write_map_header(1)
              packer.write("filename")
              packer.write(Utils::Git.relative_to_root(filename))
            end
          end

          def to_s
            "Coverage::Event[test_id=#{test_id}, test_suite_id=#{test_suite_id}, test_session_id=#{test_session_id}, coverage=#{coverage}]"
          end
        end
      end
    end
  end
end
