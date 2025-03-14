# frozen_string_literal: true

require "fileutils"
require "tempfile"

module Datadog
  module CI
    module Utils
      # FileStorage module provides functionality for storing and retrieving arbitrary Ruby objects in a temp file
      # to share them between processes.
      module FileStorage
        TEMP_DIR = File.join(Dir.tmpdir, "datadog-ci-storage")

        def self.store(key, value)
          ensure_temp_dir_exists
          file_path = file_path_for(key)

          File.binwrite(file_path, Marshal.dump(value))

          true
        rescue => e
          Datadog.logger.error("Failed to store data for key '#{key}': #{e.class} - #{e.message}")
          false
        end

        def self.retrieve(key)
          file_path = file_path_for(key)
          return nil unless File.exist?(file_path)

          Marshal.load(File.binread(file_path))
        rescue => e
          Datadog.logger.error("Failed to retrieve data for key '#{key}': #{e.class} - #{e.message}")
          nil
        end

        def self.cleanup
          return false unless Dir.exist?(TEMP_DIR)

          FileUtils.rm_rf(TEMP_DIR)
          true
        rescue => e
          Datadog.logger.error("Failed to cleanup storage directory: #{e.class} - #{e.message}")
          false
        end

        def self.ensure_temp_dir_exists
          FileUtils.mkdir_p(TEMP_DIR) unless Dir.exist?(TEMP_DIR)
        end

        def self.file_path_for(key)
          sanitized_key = key.to_s.gsub(/[^a-zA-Z0-9_-]/, "_")
          File.join(TEMP_DIR, "dd-ci-#{sanitized_key}.dat")
        end
      end
    end
  end
end
