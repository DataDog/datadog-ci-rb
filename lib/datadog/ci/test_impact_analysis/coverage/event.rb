# frozen_string_literal: true

require "msgpack"

require_relative "../../git/local_repository"

module Datadog
  module CI
    module TestImpactAnalysis
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

            %i[test_id test_suite_id test_session_id coverage].each do |key|
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
              packer.write(Git::LocalRepository.relative_to_root(filename))
            end
          end

          def to_s
            "Coverage::Event[test_id=#{test_id}, test_suite_id=#{test_suite_id}, test_session_id=#{test_session_id}, coverage=#{coverage}]"
          end

          # Return a human readable version of the event
          def pretty_print(q)
            q.group 0 do
              q.breakable
              q.text "Test ID: #{@test_id}\n"
              q.text "Test Suite ID: #{@test_suite_id}\n"
              q.text "Test Session ID: #{@test_session_id}\n"
              q.group(2, "Files: [", "]\n") do
                q.seplist @coverage.keys.each do |key|
                  q.text key
                end
              end
            end
          end
        end
      end
    end
  end
end
