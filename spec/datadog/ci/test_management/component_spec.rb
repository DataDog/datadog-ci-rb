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

    let(:test_session) { instance_double(Datadog::CI::TestSession, distributed: false) }

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

      context "when test session is distributed" do
        before do
          allow(test_session).to receive(:distributed).and_return(true)
        end

        it "stores component state" do
          expect(Datadog::CI::Utils::FileStorage).to receive(:store).with(
            described_class::FILE_STORAGE_KEY,
            {
              tests_properties: tests_properties
            }
          ).and_return(true)

          configure
        end
      end

      context "when test session is not distributed" do
        before do
          allow(test_session).to receive(:distributed).and_return(false)
        end

        it "doesn't store component state" do
          expect(Datadog::CI::Utils::FileStorage).not_to receive(:store)

          configure
        end
      end

      context "when in a client process" do
        before do
          allow(Datadog.send(:components)).to receive(:test_visibility).and_return(
            instance_double(Datadog::CI::TestVisibility::Component, client_process?: true)
          )
          allow(Datadog::CI::TestManagement::TestsProperties).to receive(:new)
        end

        context "when component state exists in file storage" do
          let(:stored_tests_properties) do
            {
              "stored.test1." => {
                "disabled" => true,
                "quarantined" => false
              },
              "stored.test2." => {
                "disabled" => false,
                "quarantined" => true
              }
            }
          end
          let(:stored_state) { {tests_properties: stored_tests_properties} }

          before do
            allow(Datadog::CI::Utils::FileStorage).to receive(:retrieve)
              .with(described_class::FILE_STORAGE_KEY)
              .and_return(stored_state)
          end

          it "loads component state from file storage" do
            configure

            expect(test_management.tests_properties).to eq(stored_tests_properties)
            expect(tests_properties_client).not_to have_received(:fetch)
          end
        end

        context "when component state does not exist in file storage" do
          before do
            allow(Datadog::CI::Utils::FileStorage).to receive(:retrieve)
              .with(described_class::FILE_STORAGE_KEY)
              .and_return(nil)
          end

          it "fetches tests properties" do
            expect(tests_properties_client).to receive(:fetch).with(test_session).and_return(tests_properties)

            configure

            expect(test_management.tests_properties).to eq(tests_properties)
          end
        end
      end

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

  describe "#attempt_to_fix?" do
    let(:component) do
      described_class.new(
        tests_properties_client: tests_properties_client,
        enabled: enabled
      )
    end

    let(:tests_properties) do
      {
        "suite.test." => {
          "disabled" => false,
          "quarantined" => false,
          "attempt_to_fix" => true
        },
        "suite.test2." => {
          "disabled" => false,
          "quarantined" => true,
          "attempt_to_fix" => false
        }
      }
    end

    let(:tests_properties_client) do
      instance_double(
        Datadog::CI::TestManagement::TestsProperties,
        fetch: tests_properties
      )
    end

    before do
      component.configure(
        instance_double(Datadog::CI::Remote::LibrarySettings, test_management_enabled?: true),
        instance_double(Datadog::CI::TestSession, distributed: false, set_tag: true)
      )
    end

    context "when test management is enabled" do
      let(:enabled) { true }

      it "returns true for test with attempt_to_fix property" do
        expect(component.attempt_to_fix?("suite.test.")).to be true
      end

      it "returns false for test without attempt_to_fix property" do
        expect(component.attempt_to_fix?("suite.test2.")).to be false
      end

      it "returns false for non-existent test" do
        expect(component.attempt_to_fix?("non.existent.test.")).to be false
      end
    end

    context "when test management is disabled" do
      let(:enabled) { false }

      it "returns false regardless of test properties" do
        expect(component.attempt_to_fix?("suite.test.")).to be false
        expect(component.attempt_to_fix?("suite.test2.")).to be false
        expect(component.attempt_to_fix?("non.existent.test.")).to be false
      end
    end
  end
end
