# frozen_string_literal: true

require_relative "concurrent_span"
require_relative "ext/test"

module Datadog
  module CI
    # Represents the whole test session process.
    # Documentation on test sessions is here:
    # https://docs.datadoghq.com/continuous_integration/explorer/?tab=testruns#sessions
    # This object can be shared between multiple threads.
    #
    # @public_api
    class TestSession < ConcurrentSpan
      attr_accessor :estimated_total_tests_count

      # Finishes the current test session.
      # @return [void]
      def finish
        test_visibility.deactivate_test_session

        super
      end

      # Return the test session's name which is equal to test command used
      # @return [String] the command for this test session.
      def name
        test_visibility.logical_test_session_name || "test_session"
      end

      # Return the test session's command used to run the tests
      # @return [String] the command for this test session.
      def test_command
        get_tag(Ext::Test::TAG_COMMAND)
      end

      # Return the test session's CI provider name (e.g. "travis", "circleci", etc.)
      # @return [String] the provider name for this test session.
      def ci_provider
        get_tag(Ext::Environment::TAG_PROVIDER_NAME)
      end

      # Return the test session's CI job name (e.g. "build", "test", etc.)
      # @return [String] the job name for this test session.
      def ci_job_name
        get_tag(Ext::Environment::TAG_JOB_NAME)
      end

      # Returns the git commit message extracted from the environment.
      # @return [String] the commit message.
      def git_commit_message
        get_tag(Ext::Git::TAG_COMMIT_MESSAGE)
      end

      def skipping_tests?
        get_tag(Ext::Test::TAG_ITR_TEST_SKIPPING_ENABLED) == "true"
      end

      def code_coverage?
        get_tag(Ext::Test::TAG_CODE_COVERAGE_ENABLED) == "true"
      end

      # Return the test session tags that could be inherited by sub-spans
      # @return [Hash] the tags to be inherited by sub-spans.
      def inheritable_tags
        return @inheritable_tags if defined?(@inheritable_tags)

        # this method is not synchronized because it does not iterate over the tags collection, but rather
        # uses synchronized method #get_tag to get each tag value
        res = {}
        Ext::Test::INHERITABLE_TAGS.each do |tag|
          res[tag] = get_tag(tag)
        end
        @inheritable_tags = res.freeze
      end
    end
  end
end
