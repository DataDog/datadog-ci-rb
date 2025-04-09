# frozen_string_literal: true

# Dummy Integration
module Fake
  class Integration < Datadog::CI::Contrib::Integration
    module Patcher
      module_function

      def patched?
        @patched
      end

      def patch
        @patched = true
      end

      def reset
        @patched = nil
      end
    end

    def version
      "0.1"
    end

    def loaded?
      true
    end

    def compatible?
      true
    end

    def late_instrument?
      false
    end

    def patcher
      Patcher
    end
  end
end

RSpec.describe Datadog::CI::Configuration::Settings do
  context "when used to extend Datadog::Core::Configuration::Settings" do
    subject(:settings) do
      # When 'datadog/ci' is required, it automatically extends Settings.
      if described_class >= Datadog::Core::Configuration::Settings
        Datadog::Core::Configuration::Settings.new
      else
        Datadog::Core::Configuration::Settings.new.tap do |settings|
          settings.extend(described_class)
        end
      end
    end

    describe "#ci" do
      describe "#enabled" do
        subject(:enabled) { settings.ci.enabled }

        it { is_expected.to be false }

        context "when #{Datadog::CI::Ext::Settings::ENV_MODE_ENABLED}" do
          around do |example|
            ClimateControl.modify(Datadog::CI::Ext::Settings::ENV_MODE_ENABLED => enable) do
              example.run
            end
          end

          context "is not defined" do
            let(:enable) { nil }

            it { is_expected.to be false }
          end

          context "is set to true" do
            let(:enable) { "true" }

            it { is_expected.to be true }
          end

          context "is set to false" do
            let(:enable) { "false" }

            it { is_expected.to be false }
          end
        end
      end

      describe "#enabled=" do
        it "updates the #enabled setting" do
          expect { settings.ci.enabled = true }
            .to change { settings.ci.enabled }
            .from(false)
            .to(true)
        end
      end

      describe "#test_session_name" do
        subject(:test_session_name) { settings.ci.test_session_name }

        it { is_expected.to be nil }

        context "when #{Datadog::CI::Ext::Settings::ENV_TEST_SESSION_NAME}" do
          around do |example|
            ClimateControl.modify(Datadog::CI::Ext::Settings::ENV_TEST_SESSION_NAME => test_session_name) do
              example.run
            end
          end

          context "is not defined" do
            let(:test_session_name) { nil }

            it { is_expected.to be nil }
          end

          context "is set to some value" do
            let(:test_session_name) { "knapsack-pro-circle-ci-runner-1" }

            it { is_expected.to eq test_session_name }
          end
        end
      end

      describe "#test_session_name=" do
        it "updates the #test_session_name setting" do
          expect { settings.ci.test_session_name = "rspec" }
            .to change { settings.ci.test_session_name }
            .from(nil)
            .to("rspec")
        end
      end

      describe "#agentless_mode_enabled" do
        subject(:agentless_mode_enabled) { settings.ci.agentless_mode_enabled }

        it { is_expected.to be false }

        context "when #{Datadog::CI::Ext::Settings::ENV_AGENTLESS_MODE_ENABLED}" do
          around do |example|
            ClimateControl.modify(Datadog::CI::Ext::Settings::ENV_AGENTLESS_MODE_ENABLED => enable) do
              example.run
            end
          end

          context "is not defined" do
            let(:enable) { nil }

            it { is_expected.to be false }
          end

          context "is set to true" do
            let(:enable) { "true" }

            it { is_expected.to be true }
          end

          context "is set to false" do
            let(:enable) { "false" }

            it { is_expected.to be false }
          end
        end
      end

      describe "#agentless_mode_enabled=" do
        it "updates the #enabled setting" do
          expect { settings.ci.agentless_mode_enabled = true }
            .to change { settings.ci.agentless_mode_enabled }
            .from(false)
            .to(true)
        end
      end

      describe "#agentless_url" do
        subject(:agentless_url) { settings.ci.agentless_url }

        it { is_expected.to be nil }

        context "when #{Datadog::CI::Ext::Settings::ENV_AGENTLESS_URL}" do
          around do |example|
            ClimateControl.modify(Datadog::CI::Ext::Settings::ENV_AGENTLESS_URL => agentless_url) do
              example.run
            end
          end

          context "is not defined" do
            let(:agentless_url) { nil }

            it { is_expected.to be nil }
          end

          context "is set to some value" do
            let(:agentless_url) { "example.com" }

            it { is_expected.to eq agentless_url }
          end
        end
      end

      describe "#agentless_url=" do
        it "updates the #agentless_url setting" do
          expect { settings.ci.agentless_url = "example.com" }
            .to change { settings.ci.agentless_url }
            .from(nil)
            .to("example.com")
        end
      end

      describe "#force_test_level_visibility" do
        subject(:force_test_level_visibility) do
          settings.ci.force_test_level_visibility
        end

        it { is_expected.to be false }

        context "when #{Datadog::CI::Ext::Settings::ENV_FORCE_TEST_LEVEL_VISIBILITY}" do
          around do |example|
            ClimateControl.modify(
              Datadog::CI::Ext::Settings::ENV_FORCE_TEST_LEVEL_VISIBILITY => enable
            ) do
              example.run
            end
          end

          context "is not defined" do
            let(:enable) { nil }

            it { is_expected.to be false }
          end

          context "is set to true" do
            let(:enable) { "true" }

            it { is_expected.to be true }
          end

          context "is set to false" do
            let(:enable) { "false" }

            it { is_expected.to be false }
          end
        end
      end

      describe "#force_test_level_visibility=" do
        it "updates the #enabled setting" do
          expect { settings.ci.force_test_level_visibility = true }
            .to change { settings.ci.force_test_level_visibility }
            .from(false)
            .to(true)
        end
      end

      describe "#itr_enabled" do
        subject(:itr_enabled) { settings.ci.itr_enabled }

        it { is_expected.to be true }

        context "when #{Datadog::CI::Ext::Settings::ENV_ITR_ENABLED}" do
          around do |example|
            ClimateControl.modify(Datadog::CI::Ext::Settings::ENV_ITR_ENABLED => enable) do
              example.run
            end
          end

          context "is not defined" do
            let(:enable) { nil }

            it { is_expected.to be true }
          end

          context "is set to true" do
            let(:enable) { "true" }

            it { is_expected.to be true }
          end

          context "is set to false" do
            let(:enable) { "false" }

            it { is_expected.to be false }
          end
        end
      end

      describe "#itr_enabled=" do
        it "updates the #enabled setting" do
          expect { settings.ci.itr_enabled = false }
            .to change { settings.ci.itr_enabled }
            .from(true)
            .to(false)
        end
      end

      describe "#git_metadata_upload_enabled" do
        subject(:git_metadata_upload_enabled) { settings.ci.git_metadata_upload_enabled }

        it { is_expected.to be true }

        context "when #{Datadog::CI::Ext::Settings::ENV_GIT_METADATA_UPLOAD_ENABLED}" do
          around do |example|
            ClimateControl.modify(Datadog::CI::Ext::Settings::ENV_GIT_METADATA_UPLOAD_ENABLED => enable) do
              example.run
            end
          end

          context "is not defined" do
            let(:enable) { nil }

            it { is_expected.to be true }
          end

          context "is set to true" do
            let(:enable) { "true" }

            it { is_expected.to be true }
          end

          context "is set to false" do
            let(:enable) { "false" }

            it { is_expected.to be false }
          end
        end
      end

      describe "#git_metadata_upload_enabled=" do
        it "updates the #enabled setting" do
          expect { settings.ci.git_metadata_upload_enabled = false }
            .to change { settings.ci.git_metadata_upload_enabled }
            .from(true)
            .to(false)
        end
      end

      describe "#itr_code_coverage_excluded_bundle_path" do
        subject(:itr_code_coverage_excluded_bundle_path) do
          settings.ci.itr_code_coverage_excluded_bundle_path
        end

        it { is_expected.to be nil }

        context "when #{Datadog::CI::Ext::Settings::ENV_ITR_CODE_COVERAGE_EXCLUDED_BUNDLE_PATH}" do
          around do |example|
            ClimateControl.modify(
              Datadog::CI::Ext::Settings::ENV_ITR_CODE_COVERAGE_EXCLUDED_BUNDLE_PATH => path
            ) do
              example.run
            end
          end

          context "is not defined" do
            let(:path) { nil }

            it { is_expected.to be nil }

            context "and when bundle location is found in project folder" do
              let(:bundle_location) { "/path/to/repo/vendor/bundle" }
              before do
                allow(Datadog::CI::Utils::Bundle).to receive(:location).and_return(bundle_location)
              end

              it { is_expected.to eq bundle_location }
            end
          end

          context "is set to some value" do
            let(:path) { "/path/to/excluded" }

            it { is_expected.to eq path }
          end
        end
      end

      describe "#itr_code_coverage_excluded_bundle_path=" do
        it "updates the #enabled setting" do
          expect { settings.ci.itr_code_coverage_excluded_bundle_path = "/path/to/excluded" }
            .to change { settings.ci.itr_code_coverage_excluded_bundle_path }
            .from(nil)
            .to("/path/to/excluded")
        end
      end

      describe "#itr_test_impact_analysis_use_allocation_tracing" do
        subject(:itr_test_impact_analysis_use_allocation_tracing) { settings.ci.itr_test_impact_analysis_use_allocation_tracing }

        it { is_expected.to be true }

        context "when #{Datadog::CI::Ext::Settings::ENV_ITR_TEST_IMPACT_ANALYSIS_USE_ALLOCATION_TRACING}" do
          around do |example|
            ClimateControl.modify(Datadog::CI::Ext::Settings::ENV_ITR_TEST_IMPACT_ANALYSIS_USE_ALLOCATION_TRACING => enable) do
              example.run
            end
          end

          context "is not defined" do
            let(:enable) { nil }

            it { is_expected.to be true }
          end

          context "is set to true" do
            let(:enable) { "true" }

            it { is_expected.to be true }
          end

          context "is set to false" do
            let(:enable) { "false" }

            it { is_expected.to be false }
          end
        end
      end

      describe "#itr_test_impact_analysis_use_allocation_tracing=" do
        it "updates the #enabled setting" do
          expect { settings.ci.itr_test_impact_analysis_use_allocation_tracing = false }
            .to change { settings.ci.itr_test_impact_analysis_use_allocation_tracing }
            .from(true)
            .to(false)
        end
      end

      describe "#retry_failed_tests_enabled" do
        subject(:retry_failed_tests_enabled) { settings.ci.retry_failed_tests_enabled }

        it { is_expected.to be true }

        context "when #{Datadog::CI::Ext::Settings::ENV_RETRY_FAILED_TESTS_ENABLED}" do
          around do |example|
            ClimateControl.modify(Datadog::CI::Ext::Settings::ENV_RETRY_FAILED_TESTS_ENABLED => enable) do
              example.run
            end
          end

          context "is not defined" do
            let(:enable) { nil }

            it { is_expected.to be true }
          end

          context "is set to true" do
            let(:enable) { "true" }

            it { is_expected.to be true }
          end

          context "is set to false" do
            let(:enable) { "false" }

            it { is_expected.to be false }
          end
        end
      end

      describe "#retry_failed_tests_enabled=" do
        it "updates the #retry_failed_tests_enabled setting" do
          expect { settings.ci.retry_failed_tests_enabled = false }
            .to change { settings.ci.retry_failed_tests_enabled }
            .from(true)
            .to(false)
        end
      end

      describe "#retry_failed_tests_max_attempts" do
        subject(:retry_failed_tests_max_attempts) { settings.ci.retry_failed_tests_max_attempts }

        it { is_expected.to eq 5 }

        context "when #{Datadog::CI::Ext::Settings::ENV_RETRY_FAILED_TESTS_MAX_ATTEMPTS}" do
          around do |example|
            ClimateControl.modify(Datadog::CI::Ext::Settings::ENV_RETRY_FAILED_TESTS_MAX_ATTEMPTS => attempts) do
              example.run
            end
          end

          context "is not defined" do
            let(:attempts) { nil }

            it { is_expected.to eq 5 }
          end

          context "is set to value" do
            let(:attempts) { "10" }

            it { is_expected.to eq attempts.to_i }
          end
        end
      end

      describe "#retry_failed_tests_max_attempts=" do
        it "updates the #retry_failed_tests_max_attempts setting" do
          expect { settings.ci.retry_failed_tests_max_attempts = 7 }
            .to change { settings.ci.retry_failed_tests_max_attempts }
            .from(5)
            .to(7)
        end
      end

      describe "#retry_failed_tests_total_limit" do
        subject(:retry_failed_tests_total_limit) { settings.ci.retry_failed_tests_total_limit }

        it { is_expected.to eq 1000 }

        context "when #{Datadog::CI::Ext::Settings::ENV_RETRY_FAILED_TESTS_TOTAL_LIMIT}" do
          around do |example|
            ClimateControl.modify(Datadog::CI::Ext::Settings::ENV_RETRY_FAILED_TESTS_TOTAL_LIMIT => attempts) do
              example.run
            end
          end

          context "is not defined" do
            let(:attempts) { nil }

            it { is_expected.to eq 1000 }
          end

          context "is set to value" do
            let(:attempts) { "10" }

            it { is_expected.to eq attempts.to_i }
          end
        end
      end

      describe "#retry_failed_tests_total_limit=" do
        it "updates the #retry_failed_tests_total_limit setting" do
          expect { settings.ci.retry_failed_tests_total_limit = 42 }
            .to change { settings.ci.retry_failed_tests_total_limit }
            .from(1000)
            .to(42)
        end
      end

      describe "#retry_new_tests_enabled" do
        subject(:retry_new_tests_enabled) { settings.ci.retry_new_tests_enabled }

        it { is_expected.to be true }

        context "when #{Datadog::CI::Ext::Settings::ENV_RETRY_NEW_TESTS_ENABLED}" do
          around do |example|
            ClimateControl.modify(Datadog::CI::Ext::Settings::ENV_RETRY_NEW_TESTS_ENABLED => enable) do
              example.run
            end
          end

          context "is not defined" do
            let(:enable) { nil }

            it { is_expected.to be true }
          end

          context "is set to true" do
            let(:enable) { "true" }

            it { is_expected.to be true }
          end

          context "is set to false" do
            let(:enable) { "false" }

            it { is_expected.to be false }
          end
        end
      end

      describe "#retry_new_tests_enabled=" do
        it "updates the #retry_failed_tests_enabled setting" do
          expect { settings.ci.retry_new_tests_enabled = false }
            .to change { settings.ci.retry_new_tests_enabled }
            .from(true)
            .to(false)
        end
      end

      describe "#test_management_enabled" do
        subject(:test_management_enabled) { settings.ci.test_management_enabled }

        it { is_expected.to be true }

        context "when #{Datadog::CI::Ext::Settings::ENV_TEST_MANAGEMENT_ENABLED}" do
          around do |example|
            ClimateControl.modify(Datadog::CI::Ext::Settings::ENV_TEST_MANAGEMENT_ENABLED => enable) do
              example.run
            end
          end

          context "is not defined" do
            let(:enable) { nil }

            it { is_expected.to be true }
          end

          context "is set to true" do
            let(:enable) { "true" }

            it { is_expected.to be true }
          end

          context "is set to false" do
            let(:enable) { "false" }

            it { is_expected.to be false }
          end
        end
      end

      describe "#test_management_enabled=" do
        it "updates the #test_management_enabled setting" do
          expect { settings.ci.test_management_enabled = false }
            .to change { settings.ci.test_management_enabled }
            .from(true)
            .to(false)
        end
      end

      describe "#test_management_attempt_to_fix_retries_count" do
        subject(:test_management_attempt_to_fix_retries_count) { settings.ci.test_management_attempt_to_fix_retries_count }

        it { is_expected.to eq 20 }

        context "when #{Datadog::CI::Ext::Settings::ENV_TEST_MANAGEMENT_ATTEMPT_TO_FIX_RETRIES}" do
          around do |example|
            ClimateControl.modify(Datadog::CI::Ext::Settings::ENV_TEST_MANAGEMENT_ATTEMPT_TO_FIX_RETRIES => attempts) do
              example.run
            end
          end

          context "is not defined" do
            let(:attempts) { nil }

            it { is_expected.to eq 20 }
          end

          context "is set to value" do
            let(:attempts) { "10" }

            it { is_expected.to eq attempts.to_i }
          end
        end
      end

      describe "#test_management_attempt_to_fix_retries_count=" do
        it "updates the #test_management_attempt_to_fix_retries_count setting" do
          expect { settings.ci.test_management_attempt_to_fix_retries_count = 42 }
            .to change { settings.ci.test_management_attempt_to_fix_retries_count }
            .from(20)
            .to(42)
        end
      end

      describe "#agentless_logs_submission_enabled" do
        subject(:agentless_logs_submission_enabled) { settings.ci.agentless_logs_submission_enabled }

        it { is_expected.to be false }

        context "when #{Datadog::CI::Ext::Settings::ENV_AGENTLESS_LOGS_SUBMISSION_ENABLED}" do
          around do |example|
            ClimateControl.modify(Datadog::CI::Ext::Settings::ENV_AGENTLESS_LOGS_SUBMISSION_ENABLED => enable) do
              example.run
            end
          end

          context "is not defined" do
            let(:enable) { nil }

            it { is_expected.to be false }
          end

          context "is set to true" do
            let(:enable) { "true" }

            it { is_expected.to be true }
          end

          context "is set to false" do
            let(:enable) { "false" }

            it { is_expected.to be false }
          end
        end
      end

      describe "#agentless_logs_submission_enabled=" do
        it "updates the #agentless_logs_submission_enabled setting" do
          expect { settings.ci.agentless_logs_submission_enabled = true }
            .to change { settings.ci.agentless_logs_submission_enabled }
            .from(false)
            .to(true)
        end
      end

      describe "#agentless_logs_submission_url" do
        subject(:agentless_logs_submission_url) { settings.ci.agentless_logs_submission_url }

        it { is_expected.to be nil }

        context "when #{Datadog::CI::Ext::Settings::ENV_AGENTLESS_LOGS_SUBMISSION_URL}" do
          around do |example|
            ClimateControl.modify(Datadog::CI::Ext::Settings::ENV_AGENTLESS_LOGS_SUBMISSION_URL => agentless_logs_submission_url) do
              example.run
            end
          end

          context "is not defined" do
            let(:agentless_logs_submission_url) { nil }

            it { is_expected.to be nil }
          end

          context "is set to some value" do
            let(:agentless_logs_submission_url) { "example.com" }

            it { is_expected.to eq agentless_logs_submission_url }
          end
        end
      end

      describe "#agentless_logs_submission_url=" do
        it "updates the #agentless_logs_submission_url setting" do
          expect { settings.ci.agentless_logs_submission_url = "example.com" }
            .to change { settings.ci.agentless_logs_submission_url }
            .from(nil)
            .to("example.com")
        end
      end

      describe "#instrument" do
        let(:integration_name) { :fake }

        let(:enabled) { true }

        subject(:instrument) { settings.ci.instrument(integration_name, enabled: enabled) }

        before do
          settings.ci.enabled = ci_enabled
        end

        after do
          Fake::Integration::Patcher.reset
        end

        context "ci enabled" do
          let(:ci_enabled) { true }

          context "when integration exists" do
            it "patches the integration" do
              expect(Fake::Integration::Patcher).to receive(:patch)

              instrument
            end

            context "when called multiple times" do
              it "does not patch the integration multiple times" do
                expect(Fake::Integration::Patcher).to receive(:patch).and_call_original.once

                instrument
                instrument
              end
            end

            context "when not loaded" do
              before { allow_any_instance_of(Fake::Integration).to receive(:loaded?).and_return(false) }

              it "does not patch the integration" do
                expect(Fake::Integration::Patcher).to_not receive(:patch)

                instrument
              end
            end

            context "when not available" do
              before { allow_any_instance_of(Fake::Integration).to receive(:available?).and_return(false) }

              it "does not patch the integration" do
                expect(Fake::Integration::Patcher).to_not receive(:patch)

                instrument
              end
            end

            context "when not compatible" do
              before { allow_any_instance_of(Fake::Integration).to receive(:compatible?).and_return(false) }

              it "does not patch the integration" do
                expect(Fake::Integration::Patcher).to_not receive(:patch)

                instrument
              end
            end

            context "when not enabled" do
              let(:enabled) { false }

              it "does not patch the integration" do
                expect(Fake::Integration::Patcher).to_not receive(:patch)

                instrument
              end
            end
          end

          context "when integration does not exist" do
            let(:integration_name) { :not_existing }

            it "does not patch the integration" do
              expect { instrument }.to raise_error(Datadog::CI::Contrib::Instrumentation::InvalidIntegrationError)
            end
          end

          context "ci is not enabled" do
            let(:ci_enabled) { false }

            it "does not patch the integration" do
              expect(Fake::Integration::Patcher).to_not receive(:patch)
              instrument
            end
          end
        end
      end

      describe "#trace_flush" do
        subject(:trace_flush) { settings.ci.trace_flush }

        context "default" do
          it { is_expected.to be nil }
        end
      end

      describe "#trace_flush=" do
        let(:trace_flush) { instance_double(Datadog::Tracing::Flush::Finished) }

        it "updates the #trace_flush setting" do
          expect { settings.ci.trace_flush = trace_flush }
            .to change { settings.ci.trace_flush }
            .from(nil)
            .to(trace_flush)
        end
      end

      describe "#writer_options" do
        subject(:writer_options) { settings.ci.writer_options }

        it { is_expected.to eq({}) }

        context "when modified" do
          it "does not modify the default by reference" do
            settings.ci.writer_options[:foo] = :bar
            expect(settings.ci.writer_options).to_not be_empty
            expect(settings.ci.options[:writer_options].default_value).to be_empty
          end
        end
      end

      describe "#writer_options=" do
        let(:options) { {priority_sampling: true} }

        it "updates the #writer_options setting" do
          expect { settings.ci.writer_options = options }
            .to change { settings.ci.writer_options }
            .from({})
            .to(options)
        end
      end
    end
  end
end
