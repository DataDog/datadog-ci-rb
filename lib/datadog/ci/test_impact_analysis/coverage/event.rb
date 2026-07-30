# frozen_string_literal: true

require "msgpack"

require_relative "../../git/local_repository"

module Datadog
  module CI
    module TestImpactAnalysis
      module Coverage
        class Event
          EMPTY_IMPACTED_FILES = [].freeze

          attr_reader :test_id, :test_suite_id, :test_session_id

          def initialize(
            test_id:,
            test_suite_id:,
            test_session_id:,
            coverage:,
            impacted_files: EMPTY_IMPACTED_FILES
          )
            @test_id = test_id
            @test_suite_id = test_suite_id
            @test_session_id = test_session_id
            @coverage = coverage
            @impacted_files = impacted_files
          end

          def coverage
            unless @impacted_files.empty?
              @impacted_files.each do |file_path|
                @coverage[file_path] = true
              end
              @impacted_files = EMPTY_IMPACTED_FILES
            end

            @coverage
          end

          def valid?
            valid = true

            %i[test_suite_id test_session_id coverage].each do |key|
              value = (key == :coverage) ? @coverage : send(key)
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

            impacted_files = if @impacted_files.empty?
              EMPTY_IMPACTED_FILES
            else
              @impacted_files.reject { |filename| @coverage.key?(filename) }
            end

            packer.write("files")
            packer.write_array_header(@coverage.size + impacted_files.size)

            @coverage.each_key do |filename|
              packer.write_map_header(1)
              packer.write("filename")
              packer.write(Git::LocalRepository.relative_to_root(filename))
            end

            impacted_files.each do |filename|
              packer.write_map_header(1)
              packer.write("filename")
              packer.write(Git::LocalRepository.relative_to_root(filename))
            end
          end

          def to_s
            coverage_value = @coverage.nil? ? nil : coverage
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
                q.seplist coverage.keys.each do |key|
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
