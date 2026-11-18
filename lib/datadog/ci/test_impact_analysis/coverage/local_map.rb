# frozen_string_literal: true

require "json"
require_relative "../../utils/git"

module Datadog
  module CI
    module TestImpactAnalysis
      module Coverage
        class LocalMap
          attr_reader :base_commit

          def self.identity(suite, name, parameters)
            return unless suite.is_a?(String) && name.is_a?(String)

            [suite, name, parameters.nil? ? nil : JSON.parse(parameters)]
          end

          def initialize(document, scope:)
            unless document.is_a?(Hash) && document.keys.sort == %w[base_commit scope tests version] && document["version"] == 1
              raise ArgumentError, "unsupported local coverage format"
            end
            raise ArgumentError, "local coverage scope differs" unless document.fetch("scope") == scope
            @base_commit = document.fetch("base_commit")
            raise ArgumentError, "invalid baseline commit" unless @base_commit.is_a?(String) && Utils::Git.valid_commit_sha?(@base_commit)

            records = document.fetch("tests")
            raise ArgumentError, "invalid test records" unless records.is_a?(Array)
            @indexes = {}
            @files = {}
            records.each_with_index do |record, index|
              validate_record(record)
              # @type var identity: identity
              identity = [record.fetch("suite"), record.fetch("name"), record.fetch("parameters")]
              raise ArgumentError, "duplicate test identity" if @indexes.key?(identity)
              @indexes[identity] = index
              record.fetch("files").each { |path| (@files[path] ||= []) << index }
            end
            @must_run = nil
          end

          def select(changed_files)
            run = Array.new(@indexes.length, false)
            changed_files.each { |path| @files[path]&.each { |index| run[index] = true } }
            @must_run = run
          end

          def skippable?(identity)
            run = @must_run
            index = @indexes[identity]
            !run.nil? && !index.nil? && !run[index]
          end

          private

          def validate_record(record)
            unless record.is_a?(Hash) && record.keys.sort == %w[files name parameters suite] &&
                record["suite"].is_a?(String) && record["name"].is_a?(String) && record["files"].is_a?(Array)
              raise ArgumentError, "invalid test record"
            end
            record.fetch("files").each do |path|
              valid_path = path.is_a?(String) && !path.empty? && !path.start_with?("/") &&
                !path.include?("\0") && path.split("/").none? { |part| part == "." || part == ".." || part.empty? }
              raise ArgumentError, "invalid dependency path" unless valid_path
            end
          end
        end
      end
    end
  end
end
