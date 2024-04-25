# frozen_string_literal: true

module Datadog
  module CI
    module Ext
      # Defines constants for test tags
      # @public_api
      module Test
        CONTEXT_ORIGIN = "ciapp-test"

        TAG_FRAMEWORK = "test.framework"
        TAG_FRAMEWORK_VERSION = "test.framework_version"
        TAG_NAME = "test.name"
        TAG_SKIP_REASON = "test.skip_reason"
        TAG_STATUS = "test.status"
        TAG_SUITE = "test.suite"
        TAG_MODULE = "test.module"
        TAG_TYPE = "test.type"
        TAG_COMMAND = "test.command"
        TAG_SOURCE_FILE = "test.source.file"
        TAG_SOURCE_START = "test.source.start"
        TAG_CODEOWNERS = "test.codeowners"
        TAG_PARAMETERS = "test.parameters"

        # ITR tags
        TAG_ITR_TEST_SKIPPING_ENABLED = "test.itr.tests_skipping.enabled"
        TAG_ITR_TEST_SKIPPING_TYPE = "test.itr.tests_skipping.type"
        TAG_ITR_TEST_SKIPPING_COUNT = "test.itr.tests_skipping.count"
        TAG_ITR_SKIPPED_BY_ITR = "test.skipped_by_itr"
        TAG_ITR_TESTS_SKIPPED = "_dd.ci.itr.tests_skipped"
        TAG_ITR_UNSKIPPABLE = "test.itr.unskippable"
        TAG_ITR_FORCED_RUN = "test.itr.forced_run"

        # Code coverage tags
        TAG_CODE_COVERAGE_ENABLED = "test.code_coverage.enabled"

        # those tags are special and used to correlate tests with the test sessions, suites, and modules
        # they are transient and not sent to the backend
        TAG_TEST_SESSION_ID = "_test.session_id"
        TAG_TEST_MODULE_ID = "_test.module_id"
        TAG_TEST_SUITE_ID = "_test.suite_id"
        TRANSIENT_TAGS = [TAG_TEST_SESSION_ID, TAG_TEST_MODULE_ID, TAG_TEST_SUITE_ID].freeze

        # tags that are common for the whole session and can be inherited from the test session
        INHERITABLE_TAGS = [TAG_FRAMEWORK, TAG_FRAMEWORK_VERSION].freeze

        # Environment runtime tags
        TAG_OS_ARCHITECTURE = "os.architecture"
        TAG_OS_PLATFORM = "os.platform"
        TAG_OS_VERSION = "os.version"
        TAG_RUNTIME_NAME = "runtime.name"
        TAG_RUNTIME_VERSION = "runtime.version"

        # internal APM tag to mark a span as a test span
        TAG_SPAN_KIND = "span.kind"
        SPAN_KIND_TEST = "test"

        # could be either "test" or "suite" depending on whether we skip individual tests or whole suites
        # we use test skipping for Ruby
        ITR_TEST_SKIPPING_MODE = "test"
        ITR_TEST_SKIP_REASON = "Skipped by Datadog's intelligent test runner"
        ITR_UNSKIPPABLE_OPTION = :datadog_itr_unskippable

        # test status as recognized by Datadog
        module Status
          PASS = "pass"
          FAIL = "fail"
          SKIP = "skip"
        end

        # test types (e.g. test, benchmark, browser)
        module Type
          TEST = "test"
          BENCHMARK = "benchmark" # DEV: not used yet, will be used when benchmarks are supported
        end
      end
    end
  end
end
