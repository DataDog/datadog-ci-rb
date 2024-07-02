# frozen_string_literal: true

require "datadog/core/environment/platform"

require_relative "ext/test"
require_relative "utils/test_run"

module Datadog
  module CI
    # Represents a single part of a test run.
    # Could be a session, suite, test, or any custom span.
    #
    # @public_api
    class Span
      attr_reader :tracer_span

      def initialize(tracer_span)
        @tracer_span = tracer_span
      end

      # @return [Integer] the ID of the span.
      def id
        tracer_span.id
      end

      # @return [Integer] the trace ID of the trace this span belongs to
      def trace_id
        tracer_span.trace_id
      end

      # @return [String] the name of the span.
      def name
        tracer_span.name
      end

      # @return [String] the service name of the span.
      def service
        tracer_span.service
      end

      # @return [String] the type of the span (for example "test" or type that was provided to [Datadog::CI.trace]).
      def type
        tracer_span.type
      end

      # Checks whether span status is not set yet.
      # @return [bool] true if span does not have status
      def undefined?
        tracer_span.get_tag(Ext::Test::TAG_STATUS).nil?
      end

      # Checks whether span status is PASS.
      # @return [bool] true if span status is PASS
      def passed?
        tracer_span.get_tag(Ext::Test::TAG_STATUS) == Ext::Test::Status::PASS
      end

      # Checks whether span status is FAIL.
      # @return [bool] true if span status is FAIL
      def failed?
        tracer_span.get_tag(Ext::Test::TAG_STATUS) == Ext::Test::Status::FAIL
      end

      # Checks whether span status is SKIP.
      # @return [bool] true if span status is SKIP
      def skipped?
        tracer_span.get_tag(Ext::Test::TAG_STATUS) == Ext::Test::Status::SKIP
      end

      # Sets the status of the span to "pass".
      # @return [void]
      def passed!
        tracer_span.set_tag(Ext::Test::TAG_STATUS, Ext::Test::Status::PASS)
      end

      # Sets the status of the span to "fail".
      # @param [Exception] exception the exception that caused the test to fail.
      # @return [void]
      def failed!(exception: nil)
        tracer_span.status = 1
        tracer_span.set_tag(Ext::Test::TAG_STATUS, Ext::Test::Status::FAIL)
        tracer_span.set_error(exception) unless exception.nil?
      end

      # Sets the status of the span to "skip".
      # @param [Exception] exception the exception that caused the test to fail.
      # @param [String] reason the reason why the test was skipped.
      # @return [void]
      def skipped!(exception: nil, reason: nil)
        tracer_span.set_tag(Ext::Test::TAG_STATUS, Ext::Test::Status::SKIP)
        tracer_span.set_error(exception) unless exception.nil?
        tracer_span.set_tag(Ext::Test::TAG_SKIP_REASON, reason) unless reason.nil?
      end

      # Gets tag value by key.
      # @param [String] key the key of the tag.
      # @return [String] the value of the tag.
      def get_tag(key)
        tracer_span.get_tag(key)
      end

      # Sets tag value by key.
      # @param [String] key the key of the tag.
      # @param [String] value the value of the tag.
      # @return [void]
      def set_tag(key, value)
        tracer_span.set_tag(key, value)
      end

      # Removes tag by key.
      # @param [String] key the key of the tag.
      # @return [void]
      def clear_tag(key)
        tracer_span.clear_tag(key)
      end

      # Sets metric value by key.
      # @param [String] key the key of the metric.
      # @param [Numeric] value the value of the metric.
      # @return [void]
      def set_metric(key, value)
        tracer_span.set_metric(key, value)
      end

      # Finishes the span.
      # @return [void]
      def finish
        tracer_span.finish
      end

      # Sets multiple tags at once.
      # @param [Hash[String, String]] tags the tags to set.
      # @return [void]
      def set_tags(tags)
        tracer_span.set_tags(tags)
      end

      # Returns the git repository URL extracted from the environment.
      # @return [String] the repository URL.
      def git_repository_url
        tracer_span.get_tag(Ext::Git::TAG_REPOSITORY_URL)
      end

      # Returns the latest commit SHA extracted from the environment.
      # @return [String] the commit SHA of the last commit.
      def git_commit_sha
        tracer_span.get_tag(Ext::Git::TAG_COMMIT_SHA)
      end

      # Returns the git branch name extracted from the environment.
      # @return [String] the branch.
      def git_branch
        tracer_span.get_tag(Ext::Git::TAG_BRANCH)
      end

      # Returns the OS architecture extracted from the environment.
      # @return [String] OS arch.
      def os_architecture
        tracer_span.get_tag(Ext::Test::TAG_OS_ARCHITECTURE)
      end

      # Returns the OS platform extracted from the environment.
      # @return [String] OS platform.
      def os_platform
        tracer_span.get_tag(Ext::Test::TAG_OS_PLATFORM)
      end

      # Returns the OS version extracted from the environment.
      # @return [String] OS version.
      def os_version
        tracer_span.get_tag(Ext::Test::TAG_OS_VERSION)
      end

      # Returns the runtime name extracted from the environment.
      # @return [String] runtime name.
      def runtime_name
        tracer_span.get_tag(Ext::Test::TAG_RUNTIME_NAME)
      end

      # Returns the runtime version extracted from the environment.
      # @return [String] runtime version.
      def runtime_version
        tracer_span.get_tag(Ext::Test::TAG_RUNTIME_VERSION)
      end

      def set_environment_runtime_tags
        tracer_span.set_tag(Ext::Test::TAG_OS_ARCHITECTURE, ::RbConfig::CONFIG["host_cpu"])
        tracer_span.set_tag(Ext::Test::TAG_OS_PLATFORM, ::RbConfig::CONFIG["host_os"])
        tracer_span.set_tag(Ext::Test::TAG_OS_VERSION, Core::Environment::Platform.kernel_release)
        tracer_span.set_tag(Ext::Test::TAG_RUNTIME_NAME, Core::Environment::Ext::LANG_ENGINE)
        tracer_span.set_tag(Ext::Test::TAG_RUNTIME_VERSION, Core::Environment::Ext::ENGINE_VERSION)
        tracer_span.set_tag(Ext::Test::TAG_COMMAND, Utils::TestRun.command)
      end

      def set_default_tags
        tracer_span.set_tag(Ext::Test::TAG_SPAN_KIND, Ext::Test::SPAN_KIND_TEST)
      end

      def to_s
        "#{self.class}(name:#{name},tracer_span:#{@tracer_span})"
      end

      private

      # provides access to the test visibility component for CI models to deactivate themselves
      def test_visibility
        Datadog.send(:components).test_visibility
      end
    end
  end
end
