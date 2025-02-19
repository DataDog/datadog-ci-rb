# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/test_management/component"

RSpec.describe Datadog::CI::TestManagement::Component do
  include_context "Telemetry spy"

  describe "#configure" do
    let(:test_management) do
      described_class.new(
        tests_properties_client: tests_properties_client,
        enabled: true
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

    subject(:configure) { test_management.configure(library_settings, test_session) }

    context "when test management functionality is enabled" do
      let(:test_management_enabled) { true }

      # it tags test_session with test management enabled tag
      before do
        expect(test_session).to receive(:set_tag).with(
          Datadog::CI::Ext::Test::TAG_TEST_MANAGEMENT_ENABLED, "true"
        ).and_return(nil)
      end

      it "fetches tests properties" do
        subject

        expect(test_management.tests_properties).to eq(tests_properties)
        expect(test_management.enabled).to be true
      end

      it_behaves_like "emits telemetry metric", :distribution, "test_management_tests.response_tests", 2

      describe "#tag_test_from_properties" do
        before do
          configure
        end
        subject(:tag) { test_management.tag_test_from_properties(test_span) }

        context "when test properties are found" do
          let(:test_span) { instance_double(Datadog::CI::Test, name: "test2", test_suite_name: "suite") }

          it "tags test span with test properties" do
            expect(test_span).to receive(:set_tag).with(Datadog::CI::Ext::Test::TAG_IS_QUARANTINED, "true")
            expect(test_span).not_to receive(:set_tag).with(Datadog::CI::Ext::Test::TAG_IS_TEST_DISABLED, "true")
            expect(test_span).not_to receive(:set_tag).with(Datadog::CI::Ext::Test::TAG_IS_ATTEMPT_TO_FIX, "true")

            tag
          end
        end

        context "when test properties are not found" do
          let(:test_span) { instance_double(Datadog::CI::Test, name: "test3", test_suite_name: "suite") }

          it "does not tag test span" do
            expect(test_span).not_to receive(:set_tag)

            tag
          end
        end

        context "when test properties are all false" do
          let(:test_span) { instance_double(Datadog::CI::Test, name: "test", test_suite_name: "suite") }

          it "does not tag test span" do
            expect(test_span).not_to receive(:set_tag)

            tag
          end
        end
      end
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
