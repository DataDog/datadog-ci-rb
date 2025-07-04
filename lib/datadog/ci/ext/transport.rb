# frozen_string_literal: true

module Datadog
  module CI
    module Ext
      module Transport
        DEFAULT_DD_SITE = "datadoghq.com"

        HEADER_DD_API_KEY = "DD-API-KEY"
        HEADER_ACCEPT_ENCODING = "Accept-Encoding"
        HEADER_CONTENT_TYPE = "Content-Type"
        HEADER_CONTENT_ENCODING = "Content-Encoding"
        HEADER_EVP_SUBDOMAIN = "X-Datadog-EVP-Subdomain"
        HEADER_CONTAINER_ID = "Datadog-Container-ID"
        HEADER_RATELIMIT_RESET = "X-RateLimit-Reset"

        EVP_PROXY_V2_PATH_PREFIX = "/evp_proxy/v2/"
        EVP_PROXY_V4_PATH_PREFIX = "/evp_proxy/v4/"
        EVP_PROXY_PATH_PREFIXES = [EVP_PROXY_V4_PATH_PREFIX, EVP_PROXY_V2_PATH_PREFIX].freeze
        EVP_PROXY_COMPRESSION_SUPPORTED = {
          EVP_PROXY_V4_PATH_PREFIX => true,
          EVP_PROXY_V2_PATH_PREFIX => false
        }

        TEST_VISIBILITY_INTAKE_HOST_PREFIX = "citestcycle-intake"
        TEST_VISIBILITY_INTAKE_PATH = "/api/v2/citestcycle"

        TEST_COVERAGE_INTAKE_HOST_PREFIX = "citestcov-intake"
        TEST_COVERAGE_INTAKE_PATH = "/api/v2/citestcov"

        LOGS_INTAKE_HOST_PREFIX = "http-intake.logs"

        DD_API_HOST_PREFIX = "api"

        DD_API_SETTINGS_PATH = "/api/v2/libraries/tests/services/setting"
        DD_API_SETTINGS_TYPE = "ci_app_test_service_libraries_settings"
        DD_API_SETTINGS_RESPONSE_DIG_KEYS = %w[data attributes].freeze
        DD_API_SETTINGS_RESPONSE_ITR_ENABLED_KEY = "itr_enabled"
        DD_API_SETTINGS_RESPONSE_CODE_COVERAGE_KEY = "code_coverage"
        DD_API_SETTINGS_RESPONSE_TESTS_SKIPPING_KEY = "tests_skipping"
        DD_API_SETTINGS_RESPONSE_REQUIRE_GIT_KEY = "require_git"
        DD_API_SETTINGS_RESPONSE_FLAKY_TEST_RETRIES_KEY = "flaky_test_retries_enabled"
        DD_API_SETTINGS_RESPONSE_KNOWN_TESTS_ENABLED_KEY = "known_tests_enabled"
        DD_API_SETTINGS_RESPONSE_EARLY_FLAKE_DETECTION_KEY = "early_flake_detection"
        DD_API_SETTINGS_RESPONSE_ENABLED_KEY = "enabled"
        DD_API_SETTINGS_RESPONSE_SLOW_TEST_RETRIES_KEY = "slow_test_retries"
        DD_API_SETTINGS_RESPONSE_FAULTY_SESSION_THRESHOLD_KEY = "faulty_session_threshold"
        DD_API_SETTINGS_RESPONSE_TEST_MANAGEMENT_KEY = "test_management"
        DD_API_SETTINGS_RESPONSE_ATTEMPT_TO_FIX_RETRIES_KEY = "attempt_to_fix_retries"
        DD_API_SETTINGS_RESPONSE_DEFAULT = {DD_API_SETTINGS_RESPONSE_ITR_ENABLED_KEY => false}.freeze
        DD_API_SETTINGS_RESPONSE_IMPACTED_TESTS_ENABLED_KEY = "impacted_tests_enabled"

        DD_API_GIT_SEARCH_COMMITS_PATH = "/api/v2/git/repository/search_commits"

        DD_API_GIT_UPLOAD_PACKFILE_PATH = "/api/v2/git/repository/packfile"

        DD_API_SKIPPABLE_TESTS_PATH = "/api/v2/ci/tests/skippable"
        DD_API_SKIPPABLE_TESTS_TYPE = "test_params"

        DD_API_UNIQUE_TESTS_PATH = "/api/v2/ci/libraries/tests"
        DD_API_UNIQUE_TESTS_TYPE = "ci_app_libraries_tests_request"

        DD_API_TEST_MANAGEMENT_TESTS_PATH = "/api/v2/test/libraries/test-management/tests"
        DD_API_TEST_MANAGEMENT_TESTS_TYPE = "ci_app_libraries_tests_request"

        CONTENT_TYPE_MESSAGEPACK = "application/msgpack"
        CONTENT_TYPE_JSON = "application/json"
        CONTENT_TYPE_MULTIPART_FORM_DATA = "multipart/form-data"
        CONTENT_ENCODING_GZIP = "gzip"

        GZIP_MAGIC_NUMBER = "\x1F\x8B".b
      end
    end
  end
end
