# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/test_management/component"

RSpec.describe Datadog::CI::TestManagement::Component do
  include_context "Telemetry spy"

  describe "#configure" do
    let(:test_management) do
      described_class.new(
        tests_properties_client: tests_properties_client,
        enabled: true,
        attempt_to_fix_retries_count: 20
      )
    end

    let(:tests_properties) do
      {
        "suite.test." => {
          "disabled" => false,
          "quarantined" => false,
          "attempt_to_fix" => false
        },
        "suite.test2." => {
          "disabled" => false,
          "quarantined" => true
        }
      }
    end
    let(:tests_properties_client) do
      instance_double(
        Datadog::CI::TestManagement::TestsProperties,
        fetch: tests_properties
      )
    end

    let(:library_settings) do
      instance_double(
        Datadog::CI::Remote::LibrarySettings,
        test_management_enabled?: test_management_enabled
      )
    end
    let(:test_management_enabled) { true }

    let(:test_session) { instance_double(Datadog::CI::TestSession) }

    subject { test_management.configure(library_settings, test_session) }

    context "when test management functionality is enabled" do
      let(:test_management_enabled) { true }

      it "fetches tests properties" do
        subject

        expect(test_management.tests_properties).to eq(tests_properties)
        expect(test_management.enabled).to be true
      end

      it_behaves_like "emits telemetry metric", :distribution, "test_management_tests.response_tests", 2
    end

    context "when test management functionality is disabled" do
      let(:test_management_enabled) { false }

      it "does not fetch tests properties" do
        subject

        expect(test_management.tests_properties).to be_empty
        expect(test_management.enabled).to be false
      end
    end
  end
end
