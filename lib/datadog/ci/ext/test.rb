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

        # known and new tests
        TAG_IS_NEW = "test.is_new" # true if test is new (it was not known to Datadog before)

        # Tags for retries
        TAG_IS_RETRY = "test.is_retry" # true if test was retried by datadog-ci library
        TAG_RETRY_REASON = "test.retry_reason" # reason why test was retried
        TAG_EARLY_FLAKE_ENABLED = "test.early_flake.enabled" # true if early flake detection is enabled
        TAG_EARLY_FLAKE_ABORT_REASON = "test.early_flake.abort_reason" # reason why early flake detection was aborted

        # Tags for total code coverage
        TAG_CODE_COVERAGE_LINES_PCT = "test.code_coverage.lines_pct"

        # Tags for test managament
        TAG_TEST_MANAGEMENT_ENABLED = "test.test_management.enabled" # true if test management is enabled, set on test_session_end event
        TAG_IS_ATTEMPT_TO_FIX = "test.test_management.is_attempt_to_fix" # true if test is marked as "attempted to fix"
        TAG_IS_TEST_DISABLED = "test.test_management.is_test_disabled" # true if test is marked as disabled in test management view
        TAG_IS_QUARANTINED = "test.test_management.is_quarantined" # true if test is quarantined in test management view
        TAG_HAS_FAILED_ALL_RETRIES = "test.has_failed_all_retries" # true if test was retried and none of the retries passed
        TAG_ATTEMPT_TO_FIX_PASSED = "test.test_management.attempt_to_fix_passed" # true if test was marked as "attempted to fix" and all of the retries passed

        # a set of tag indicating which capabilities (features) are supported by the library
        module LibraryCapabilities
          TAG_TEST_IMPACT_ANALYSIS = "_dd.library_capabilities.test_impact_analysis"
          TAG_EARLY_FLAKE_DETECTION = "_dd.library_capabilities.early_flake_detection"
          TAG_AUTO_TEST_RETRIES = "_dd.library_capabilities.auto_test_retries"
          TAG_TEST_MANAGEMENT_QUARANTINE = "_dd.library_capabilities.test_management.quarantine"
          TAG_TEST_MANAGEMENT_DISABLE = "_dd.library_capabilities.test_management.disable"
          TAG_TEST_MANAGEMENT_ATTEMPT_TO_FIX = "_dd.library_capabilities.test_management.attempt_to_fix"

          # Version numbers for library capabilities
          module Versions
            TEST_IMPACT_ANALYSIS_VERSION = "1"
            EARLY_FLAKE_DETECTION_VERSION = "1"
            AUTO_TEST_RETRIES_VERSION = "1"
            TEST_MANAGEMENT_QUARANTINE_VERSION = "1"
            TEST_MANAGEMENT_DISABLE_VERSION = "1"
            TEST_MANAGEMENT_ATTEMPT_TO_FIX_VERSION = "2"
          end

          # Map of capabilities to their versions
          CAPABILITY_VERSIONS = {
            TAG_TEST_IMPACT_ANALYSIS => Versions::TEST_IMPACT_ANALYSIS_VERSION,
            TAG_EARLY_FLAKE_DETECTION => Versions::EARLY_FLAKE_DETECTION_VERSION,
            TAG_AUTO_TEST_RETRIES => Versions::AUTO_TEST_RETRIES_VERSION,
            TAG_TEST_MANAGEMENT_QUARANTINE => Versions::TEST_MANAGEMENT_QUARANTINE_VERSION,
            TAG_TEST_MANAGEMENT_DISABLE => Versions::TEST_MANAGEMENT_DISABLE_VERSION,
            TAG_TEST_MANAGEMENT_ATTEMPT_TO_FIX => Versions::TEST_MANAGEMENT_ATTEMPT_TO_FIX_VERSION
          }.freeze
        end

        # internal APM tag to mark a span as a test span
        TAG_SPAN_KIND = "span.kind"
        SPAN_KIND_TEST = "test"

        # DD_TEST_SESSION_NAME value
        TAG_TEST_SESSION_NAME = "test_session.name"

        # internal tag indicating if datadog service was configured by the user
        TAG_USER_PROVIDED_TEST_SERVICE = "_dd.test.is_user_provided_service"

        # internal metric with the number of virtual CPUs
        METRIC_CPU_COUNT = "_dd.host.vcpu_count"

        # tags that are common for the whole session and can be inherited from the test session
        INHERITABLE_TAGS = [TAG_FRAMEWORK, TAG_FRAMEWORK_VERSION].freeze

        # could be either "test" or "suite" depending on whether we skip individual tests or whole suites
        ITR_TEST_SKIPPING_MODE = "test" # we always skip tests (not suites) in Ruby
        ITR_UNSKIPPABLE_OPTION = :datadog_itr_unskippable

        EARLY_FLAKE_FAULTY = "faulty"

        # test status as recognized by Datadog
        module Status
          PASS = "pass"
          FAIL = "fail"
          SKIP = "skip"
        end

        # test statuses that we use for execution stats but don't report to Datadog (e.g. fail_ignored)
        module ExecutionStatsStatus
          FAIL_IGNORED = "fail_ignored"
        end

        # test types (e.g. test, benchmark, browser)
        module Type
          TEST = "test"
          BROWSER = "browser"
          BENCHMARK = "benchmark" # DEV: not used yet, will be used when benchmarks are supported
        end

        # possible reasons why a test was retried
        module RetryReason
          RETRY_DETECT_FLAKY = "early_flake_detection"
          RETRY_FAILED = "auto_test_retries"
          RETRY_FLAKY_FIXED = "attempt_to_fix"
          RETRY_EXTERNAL = "external"
        end

        # possible reasons why a test was skipped
        module SkipReason
          TEST_IMPACT_ANALYSIS = "Skipped by Datadog's Test Impact Analysis"
          TEST_MANAGEMENT_DISABLED = "Flaky test is disabled by Datadog"
        end
      end
    end
  end
end
