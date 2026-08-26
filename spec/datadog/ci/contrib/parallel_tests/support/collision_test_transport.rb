# frozen_string_literal: true

require "json"
require "socket"

require "datadog/ci"

module ParallelTestsCollisionTest
  class Response
    attr_reader :payload, :code, :request_compressed, :duration_ms, :response_size, :request_size

    def initialize(payload)
      @payload = payload
      @code = 200
      @request_compressed = false
      @duration_ms = 0.0
      @response_size = payload.bytesize
      @request_size = 0
    end

    def ok?
      true
    end

    def gzipped_content?
      false
    end

    def telemetry_error_type
      nil
    end

    def internal_error?
      false
    end

    def server_error?
      false
    end

    def trace_count
      0
    end
  end

  class Api
    def api_request(path:, payload:, **_options)
      response_payload = case path
      when Datadog::CI::Ext::Transport::DD_API_SETTINGS_PATH
        settings_response
      when Datadog::CI::Ext::Transport::DD_API_TEST_MANAGEMENT_TESTS_PATH
        test_management_response
      else
        {"data" => {"attributes" => {}}}
      end

      Response.new(JSON.generate(response_payload))
    end

    def citestcycle_request(**_options)
      Response.new("")
    end

    private

    def settings_response
      atr_enabled = ENV.fetch("DD_COLLISION_TEST_RUN") == "B"

      {
        "data" => {
          "id" => "collision-test-settings",
          "type" => Datadog::CI::Ext::Transport::DD_API_SETTINGS_TYPE,
          "attributes" => {
            "itr_enabled" => false,
            "code_coverage" => false,
            "tests_skipping" => false,
            "require_git" => false,
            "flaky_test_retries_enabled" => atr_enabled,
            "known_tests_enabled" => false,
            "impacted_tests_enabled" => false,
            "coverage_report_upload_enabled" => false,
            "early_flake_detection" => {"enabled" => false},
            "test_management" => {
              "enabled" => true,
              "attempt_to_fix_retries" => 0
            }
          }
        }
      }
    end

    def test_management_response
      suites = if ENV.fetch("DD_COLLISION_TEST_RUN") == "A"
        {
          ENV.fetch("DD_COLLISION_TEST_TARGET_SUITE") => {
            "tests" => {
              "always fails" => {
                "properties" => {
                  "disabled" => false,
                  "quarantined" => true,
                  "attempt_to_fix" => false
                }
              }
            }
          }
        }
      else
        {}
      end

      {
        "data" => {
          "id" => "collision-test-management",
          "type" => Datadog::CI::Ext::Transport::DD_API_TEST_MANAGEMENT_TESTS_TYPE,
          "attributes" => {
            "modules" => {
              "rspec" => {"suites" => suites}
            }
          }
        }
      }
    end
  end

  module ApiBuilder
    def build_agentless_api(_settings)
      Api.new
    end
  end

  module FileStorageBarrier
    def store(key, value)
      result = super
      wait_at_barrier if result && key == Datadog::CI::TestManagement::Component::FILE_STORAGE_KEY
      result
    end

    private

    def wait_at_barrier
      return if ENV[Datadog::CI::Ext::Settings::ENV_TEST_VISIBILITY_DRB_SERVER_URI]

      UNIXSocket.open(ENV.fetch("DD_COLLISION_TEST_BARRIER")) do |socket|
        socket.puts(ENV.fetch("DD_COLLISION_TEST_RUN"))
        response = socket.gets&.chomp
        raise "Unexpected collision test barrier response: #{response.inspect}" unless response == "continue"
      end
    end
  end
end

Datadog::CI::Transport::Api::Builder.singleton_class.prepend(ParallelTestsCollisionTest::ApiBuilder)
Datadog::CI::Utils::FileStorage.singleton_class.prepend(ParallelTestsCollisionTest::FileStorageBarrier)
