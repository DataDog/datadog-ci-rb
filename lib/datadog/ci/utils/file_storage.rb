# frozen_string_literal: true

require "fileutils"
require "securerandom"
require "tmpdir"

module Datadog
  module CI
    module Utils
      # FileStorage module provides functionality for storing and retrieving arbitrary Ruby objects in a temp file
      # to share them between processes.
      module FileStorage
        class MissingNamespaceError < StandardError; end

        TEMP_DIR = File.join(Dir.tmpdir, "datadog-ci-storage")
        ENV_NAMESPACE = "DD_CIVISIBILITY_PARALLEL_TESTS_RUN_ID"

        def self.store(key, value)
          ensure_temp_dir_exists
          file_path = file_path_for(key)
          temporary_path = File.join(storage_dir, "dd-ci-#{SecureRandom.uuid}.tmp")

          File.open(temporary_path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
            file.binmode
            file.write(Marshal.dump(value))
            file.flush
            file.fsync
          end
          File.rename(temporary_path, file_path)

          true
        rescue => e
          Datadog.logger.error("Failed to store data for key '#{key}': #{e.class}")
          false
        ensure
          FileUtils.rm_f(temporary_path) if temporary_path
        end

        def self.retrieve(key)
          file_path = file_path_for(key)
          return nil unless File.exist?(file_path)

          Marshal.load(File.binread(file_path))
        rescue => e
          Datadog.logger.error("Failed to retrieve data for key '#{key}': #{e.class}")
          nil
        end

        def self.cleanup(namespace)
          directory = storage_dir(namespace)
          return false unless Dir.exist?(directory)

          FileUtils.rm_rf(directory)
          true
        rescue => e
          Datadog.logger.error("Failed to cleanup storage directory: #{e.class}")
          false
        end
        private_class_method :cleanup

        def self.with_new_namespace
          previous_namespace = ENV[ENV_NAMESPACE]
          namespace = SecureRandom.uuid
          ENV[ENV_NAMESPACE] = namespace

          yield namespace
        ensure
          cleanup(namespace) if namespace

          if previous_namespace
            ENV[ENV_NAMESPACE] = previous_namespace
          else
            ENV.delete(ENV_NAMESPACE)
          end
        end

        def self.ensure_temp_dir_exists
          FileUtils.mkdir_p(storage_dir)
        end

        def self.file_path_for(key)
          sanitized_key = key.to_s.gsub(/[^a-zA-Z0-9_-]/, "_")
          File.join(storage_dir, "dd-ci-#{sanitized_key}.dat")
        end

        def self.storage_dir(namespace = ENV[ENV_NAMESPACE])
          if namespace.nil? || namespace.empty?
            raise MissingNamespaceError, "File storage namespace is not set"
          end

          sanitized_namespace = namespace.gsub(/[^a-zA-Z0-9_-]/, "_")
          File.join(TEMP_DIR, sanitized_namespace)
        end
      end
    end
  end
end
