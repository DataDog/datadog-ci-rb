# frozen_string_literal: true

module Datadog
  module CI
    module Ext
      # Defines constants for test tags
      # @public_api
      module Test
        CONTEXT_ORIGIN = "ciapp-test"

        # Test visibility tags
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

        # Test optimisation tags
        TAG_CODE_COVERAGE_ENABLED = "test.code_coverage.enabled"
        TAG_ITR_TEST_SKIPPING_ENABLED = "test.itr.tests_skipping.enabled"
        TAG_ITR_TEST_SKIPPING_TYPE = "test.itr.tests_skipping.type"
        TAG_ITR_TEST_SKIPPING_COUNT = "test.itr.tests_skipping.count"
        TAG_ITR_SKIPPED_BY_ITR = "test.skipped_by_itr"
        TAG_ITR_TESTS_SKIPPED = "_dd.ci.itr.tests_skipped"
        TAG_ITR_UNSKIPPABLE = "test.itr.unskippable"
        TAG_ITR_FORCED_RUN = "test.itr.forced_run"

        # Internal tags, they are not sent to the backend.
        # These tags are internal to this library and used to correlate tests with
        # the test sessions, suites, and modules.
        TAG_TEST_SESSION_ID = "_test.session_id"
        TAG_TEST_MODULE_ID = "_test.module_id"
        TAG_TEST_SUITE_ID = "_test.suite_id"
        TRANSIENT_TAGS = [TAG_TEST_SESSION_ID, TAG_TEST_MODULE_ID, TAG_TEST_SUITE_ID].freeze

        # Environment runtime tags
        TAG_OS_ARCHITECTURE = "os.architecture"
        TAG_OS_PLATFORM = "os.platform"
        TAG_OS_VERSION = "os.version"
        TAG_RUNTIME_NAME = "runtime.name"
        TAG_RUNTIME_VERSION = "runtime.version"

        # Tags for browser tests
        TAG_IS_RUM_ACTIVE = "test.is_rum_active" # true if Datadog RUM was detected in the page(s) loaded by Selenium
        TAG_BROWSER_DRIVER = "test.browser.driver"
        # version of selenium driver used
        TAG_BROWSER_DRIVER_VERSION = "test.browser.driver_version"
        # name of the browser (Chrome, Firefox, Edge, etc), if multiple browsers then this tag is empty
        TAG_BROWSER_NAME = "test.browser.name"
        # version of the browser, if multiple browsers or multiple versions then this tag is empty
        TAG_BROWSER_VERSION = "test.browser.version"

        # Tags for test retries
        TAG_IS_RETRY = "test.is_retry" # true if test was retried by datadog-ci library
        TAG_IS_NEW = "test.is_new" # true if test was marked as new by new test retries (early flake detection)

        # internal APM tag to mark a span as a test span
        TAG_SPAN_KIND = "span.kind"
        SPAN_KIND_TEST = "test"

        # tags that are common for the whole session and can be inherited from the test session
        INHERITABLE_TAGS = [TAG_FRAMEWORK, TAG_FRAMEWORK_VERSION].freeze

        # could be either "test" or "suite" depending on whether we skip individual tests or whole suites
        ITR_TEST_SKIPPING_MODE = "test" # we always skip tests (not suites) in Ruby
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
          BROWSER = "browser"
          BENCHMARK = "benchmark" # DEV: not used yet, will be used when benchmarks are supported
        end
      end
    end
  end
end
