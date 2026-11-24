# frozen_string_literal: true

require "ripper"

module EnvironmentVariablePrefixes
  ALLOWED_PREFIXES = %w[DD_CIVISIBILITY_ DD_TEST_ DD_TESTOPTIMIZATION_].freeze

  # These exact names predate this rule. New variables must use an allowed prefix.
  EXISTING_NAMES = %w[
    DD_ACTION_EXECUTION_ID
    DD_AGENTLESS_LOG_SUBMISSION_ENABLED
    DD_AGENTLESS_LOG_SUBMISSION_URL
    DD_CI_ACTIVESUPPORT_ENABLED
    DD_CI_LOGRAGE_ENABLED
    DD_CI_SEMANTIC_LOGGER_ENABLED
    DD_CODE_COVERAGE_FLAGS
    DD_CUSTOM_PARENT_ID
    DD_CUSTOM_TRACE_ID
    DD_GIT_BRANCH
    DD_GIT_COMMIT_AUTHOR_DATE
    DD_GIT_COMMIT_AUTHOR_EMAIL
    DD_GIT_COMMIT_AUTHOR_NAME
    DD_GIT_COMMIT_COMMITTER_DATE
    DD_GIT_COMMIT_COMMITTER_EMAIL
    DD_GIT_COMMIT_COMMITTER_NAME
    DD_GIT_COMMIT_HEAD_SHA
    DD_GIT_COMMIT_MESSAGE
    DD_GIT_COMMIT_SHA
    DD_GIT_PULL_REQUEST_BASE_BRANCH
    DD_GIT_PULL_REQUEST_BASE_BRANCH_SHA
    DD_GIT_REPOSITORY_URL
    DD_GIT_TAG
    DD_PIPELINE_EXECUTION_ID
    DD_TRACE_CI_ENABLED
    DD_TRACE_CUCUMBER_ENABLED
    DD_TRACE_MINITEST_ENABLED
    DD_TRACE_PARALLEL_TESTS_ENABLED
    DD_TRACE_RSPEC_DATADOG_FORMATTER_ENABLED
    DD_TRACE_RSPEC_ENABLED
    DD_TRACE_SETUP_TEARDOWN_ENABLED
  ].freeze

  def self.violations(source)
    Ripper.lex(source).each_with_object([]) do |(position, type, name, _state), errors|
      next unless type == :on_tstring_content && /\ADD_[A-Z0-9_]+\z/.match?(name)
      next if name.start_with?(*ALLOWED_PREFIXES) || EXISTING_NAMES.include?(name)

      line, column = position
      errors << "#{line}:#{column + 1}: #{name} must start with #{ALLOWED_PREFIXES.join(", ")}"
    end
  end

  def self.check_files(paths)
    paths.flat_map do |path|
      violations(File.read(path)).map { |error| "#{path}:#{error}" }
    end
  end
end

if $PROGRAM_NAME == __FILE__
  paths = ARGV.empty? ? Dir[File.expand_path("../lib/**/*.rb", __dir__)].sort : ARGV
  errors = EnvironmentVariablePrefixes.check_files(paths)
  warn errors.join("\n") unless errors.empty?
  exit(errors.empty? ? 0 : 1)
end
