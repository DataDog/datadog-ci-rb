# frozen_string_literal: true

require "json"

module Datadog
  module CI
    module Utils
      module Json
        def self.read_file(file_path)
          unless File.exist?(file_path)
            Datadog.logger.debug { "JSON file not found: #{file_path}" }
            return nil
          end

          JSON.parse(File.read(file_path))
        rescue JSON::ParserError, SystemCallError => e
          Datadog.logger.debug { "Failed to load JSON file #{file_path}: #{e.message}" }
          nil
        end
      end
    end
  end
end
