# frozen_string_literal: true

require "securerandom"
require "rbconfig"
require "socket"
require "etc"

module Datadog
  module CI
    module Utils
      module Identity
        PROCESS_ID = ::Process.method(:pid)
        private_constant :PROCESS_ID

        def self.pid
          PROCESS_ID.call
        end

        def self.id
          process_id = pid
          if @pid != process_id
            @pid = process_id
            @id = SecureRandom.uuid
          end
          @id ||= SecureRandom.uuid
        end

        def self.lang
          "ruby"
        end

        def self.lang_engine
          RUBY_ENGINE
        end

        def self.lang_version
          RUBY_VERSION
        end

        def self.lang_interpreter
          RUBY_DESCRIPTION
        end

        def self.gem_datadog_version
          CI::VERSION::STRING
        end
      end

      module Platform
        def self.hostname
          Socket.gethostname
        end

        def self.kernel_release
          Etc.uname[:release]
        rescue
          RbConfig::CONFIG["host_os"]
        end
      end
    end
  end
end
