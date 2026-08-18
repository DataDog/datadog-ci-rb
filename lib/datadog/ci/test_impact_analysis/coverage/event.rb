# frozen_string_literal: true

require "msgpack"

require_relative "files"

module Datadog
  module CI
    module TestImpactAnalysis
      module Coverage
        class Event
          attr_reader :test_id, :test_suite_id, :test_session_id

          def initialize(
            test_id:,
            test_suite_id:,
            test_session_id:,
            files:
          )
            @test_id = test_id
            @test_suite_id = test_suite_id
            @test_session_id = test_session_id
            @files = files
          end

          def inspect_coverage
            @files.inspect_coverage
          end

          def valid?
            valid = true

            %i[test_suite_id test_session_id files].each do |key|
              value = (key == :files) ? @files : send(key)
              next unless value.nil?

              Datadog.logger.warn("citestcov event is invalid: [#{key}] is nil. Event: #{self}")
              valid = false
            end

            valid
          end

          def to_msgpack(packer = nil)
            packer ||= MessagePack::Packer.new

            packer.write_map_header(test_id.nil? ? 3 : 4)

            packer.write("test_session_id")
            packer.write(test_session_id.to_i)

            packer.write("test_suite_id")
            packer.write(test_suite_id.to_i)

            unless test_id.nil?
              packer.write("span_id")
              packer.write(test_id.to_i)
            end

            packer.write("files")
            @files.write_to(packer)
          end

          def to_s
            coverage_value = @files.nil? ? nil : inspect_coverage
            "Coverage::Event[test_id=#{test_id}, test_suite_id=#{test_suite_id}, test_session_id=#{test_session_id}, coverage=#{coverage_value}]"
          end

          # Return a human readable version of the event
          def pretty_print(q)
            q.group 0 do
              q.breakable
              q.text "Test ID: #{@test_id}\n"
              q.text "Test Suite ID: #{@test_suite_id}\n"
              q.text "Test Session ID: #{@test_session_id}\n"
              q.group(2, "Files: [", "]\n") do
                q.seplist @files do |filename|
                  q.text filename
                end
              end
            end
          end
        end
      end
    end
  end
end
