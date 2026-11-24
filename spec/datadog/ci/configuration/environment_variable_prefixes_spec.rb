# frozen_string_literal: true

require "tmpdir"

require_relative "../../../../tasks/lint_env"

RSpec.describe EnvironmentVariablePrefixes do
  describe ".violations" do
    subject(:violations) { described_class.violations(source) }

    %w[DD_CIVISIBILITY_ DD_TEST_ DD_TESTOPTIMIZATION_].each do |prefix|
      context "with the #{prefix} prefix" do
        let(:source) { %(ENV_ENABLED = "#{prefix}NEW_FEATURE_ENABLED") }

        it { is_expected.to be_empty }
      end
    end

    %w[DD_TIA_OPENED_FILES_COVERAGE_ENABLED DD_NEW_FEATURE_ENABLED DD_TRACE_CI_NEW_FEATURE_ENABLED DD_GIT_NEW_FEATURE_ENABLED].each do |name|
      context "with #{name}" do
        let(:source) { %(ENV_ENABLED = "#{name}") }

        it "reports the name and its location" do
          expect(violations).to contain_exactly(
            "1:16: #{name} must start with DD_CIVISIBILITY_, DD_TEST_, DD_TESTOPTIMIZATION_"
          )
        end
      end
    end

    context "with existing shared and legacy names" do
      let(:source) { "NAMES = %w[DD_GIT_COMMIT_SHA DD_TRACE_CI_ENABLED DD_AGENTLESS_LOG_SUBMISSION_ENABLED]" }

      it { is_expected.to be_empty }
    end

    context "with single quotes and a word array" do
      let(:source) { "FIRST = 'DD_NEW_FIRST'\nNAMES = %w[DD_NEW_SECOND DD_TEST_VALID]" }

      it "reports both invalid names" do
        expect(violations.size).to eq(2)
        expect(violations.first).to start_with("1:10: DD_NEW_FIRST ")
        expect(violations.last).to start_with("2:12: DD_NEW_SECOND ")
      end
    end

    context "with comments, constants, and other strings" do
      let(:source) { "# DD_EXAMPLE\nDD_CONSTANT = 'RUBYOPT'\nMESSAGE = 'Set DD_EXAMPLE to true'" }

      it { is_expected.to be_empty }
    end
  end

  describe ".check_files" do
    it "accepts all Datadog variables in the library" do
      paths = Dir[File.expand_path("../../../../lib/**/*.rb", __dir__)].sort

      expect(paths).not_to be_empty
      expect(described_class.check_files(paths)).to be_empty
    end

    it "includes the file path in each diagnostic" do
      Dir.mktmpdir do |directory|
        path = File.join(directory, "settings.rb")
        File.write(path, 'ENV_ENABLED = "DD_NEW_FEATURE_ENABLED"')

        expect(described_class.check_files([path])).to contain_exactly(
          a_string_starting_with("#{path}:1:16: DD_NEW_FEATURE_ENABLED ")
        )
      end
    end
  end
end
