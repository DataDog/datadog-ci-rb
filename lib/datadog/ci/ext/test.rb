# frozen_string_literal: true

module Datadog
  module CI
    module Ext
      # Defines constants for test tags
      # @public_api
      module Test
        CONTEXT_ORIGIN = "ciapp-test"

        TAG_ARGUMENTS = "test.arguments"
        TAG_FRAMEWORK = "test.framework"
        TAG_FRAMEWORK_VERSION = "test.framework_version"
        TAG_NAME = "test.name"
        TAG_SKIP_REASON = "test.skip_reason" # DEV: Not populated yet
        TAG_STATUS = "test.status"
        TAG_SUITE = "test.suite"
        TAG_MODULE = "test.module"
        TAG_TRAITS = "test.traits"
        TAG_TYPE = "test.type"
        TAG_COMMAND = "test.command"

        TEST_TYPE = "test"

        # those tags are special and they are used to correlate tests with the test sessions, suites, and modules
        TAG_TEST_SESSION_ID = "_test.session_id"
        TAG_TEST_MODULE_ID = "_test.module_id"
        TAG_TEST_SUITE_ID = "_test.suite_id"
        SPECIAL_TAGS = [TAG_TEST_SESSION_ID, TAG_TEST_MODULE_ID, TAG_TEST_SUITE_ID].freeze

        # tags that can be inherited from the test session
        INHERITABLE_TAGS = [TAG_FRAMEWORK, TAG_FRAMEWORK_VERSION, TAG_TYPE].freeze

        # Environment runtime tags
        TAG_OS_ARCHITECTURE = "os.architecture"
        TAG_OS_PLATFORM = "os.platform"
        TAG_RUNTIME_NAME = "runtime.name"
        TAG_RUNTIME_VERSION = "runtime.version"

        TAG_SPAN_KIND = "span.kind"

        module Status
          PASS = "pass"
          FAIL = "fail"
          SKIP = "skip"
        end
      end
    end
  end
end
