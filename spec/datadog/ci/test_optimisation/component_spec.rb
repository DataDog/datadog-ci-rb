# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/test_optimisation/component"

RSpec.describe Datadog::CI::TestOptimisation::Component do
  include_context "Telemetry spy"

  subject(:component) { described_class.new(api: api, dd_env: "dd_env", coverage_writer: writer, enabled: local_itr_enabled) }

  let(:local_itr_enabled) { true }

  let(:api) { double("api") }
  let(:writer) { spy("writer") }
  let(:git_worker) { spy("git_worker") }

  let(:tracer_span) { Datadog::Tracing::SpanOperation.new("session") }
  let(:test_session) { Datadog::CI::TestSession.new(tracer_span) }

  let(:remote_configuration) do
    double(
      :remote_configuration,
      itr_enabled?: itr_enabled,
      code_coverage_enabled?: code_coverage_enabled,
      tests_skipping_enabled?: tests_skipping_enabled
    )
  end
  let(:itr_enabled) { true }
  let(:code_coverage_enabled) { true }
  let(:tests_skipping_enabled) { true }

  let(:configure) { component.configure(remote_configuration, test_session) }

  before do
    allow(writer).to receive(:write)
    allow(Datadog.send(:components)).to receive(:git_tree_upload_worker).and_return(git_worker)
  end

  describe "#configure" do
    context "when ITR is disabled in remote configuration" do
      let(:itr_enabled) { false }

      it "disables the component" do
        configure

        expect(component.enabled?).to be false
        expect(component.skipping_tests?).to be false
        expect(component.code_coverage?).to be false
      end
    end

    context "when remote configuration call returned correct response without tests skipping" do
      let(:tests_skipping_enabled) { false }

      before do
        configure
      end

      it "configures the component" do
        expect(component.enabled?).to be true
        expect(component.skipping_tests?).to be false
        expect(component.code_coverage?).to be(!PlatformHelpers.jruby?) # code coverage is not supported in JRuby
      end

      it "sets test session tags" do
        expect(test_session.skipping_tests?).to be false
        expect(test_session.code_coverage?).to be true
        expect(test_session.get_tag(Datadog::CI::Ext::Test::TAG_ITR_TEST_SKIPPING_TYPE)).to eq(
          Datadog::CI::Ext::Test::ITR_TEST_SKIPPING_MODE
        )
      end
    end

    context "when remote configuration call returned correct response with tests skipping" do
      let(:skippable) do
        instance_double(
          Datadog::CI::TestOptimisation::Skippable,
          fetch_skippable_tests: instance_double(
            Datadog::CI::TestOptimisation::Skippable::Response,
            correlation_id: "42",
            tests: Set.new(["suite.test.", "suite.test2."]),
            ok?: true
          )
        )
      end

      before do
        expect(Datadog::CI::TestOptimisation::Skippable).to receive(:new).and_return(skippable)

        configure
      end

      it "configures the component" do
        expect(component.enabled?).to be true
        expect(component.skipping_tests?).to be true

        expect(component.correlation_id).to eq("42")
        expect(component.skippable_tests).to eq(Set.new(["suite.test.", "suite.test2."]))

        expect(git_worker).to have_received(:wait_until_done)
      end

      it_behaves_like "emits telemetry metric", :inc, "itr_skippable_tests.response_tests", 2
    end

    context "when test session is distributed" do
      let(:tests_skipping_enabled) { true }
      let(:skippable_response) do
        instance_double(
          Datadog::CI::TestOptimisation::Skippable::Response,
          correlation_id: "42",
          tests: Set.new(["suite.test.", "suite.test2."]),
          ok?: true
        )
      end
      let(:skippable) do
        instance_double(
          Datadog::CI::TestOptimisation::Skippable,
          fetch_skippable_tests: skippable_response
        )
      end

      before do
        allow(test_session).to receive(:distributed).and_return(true)
        allow(Datadog::CI::TestOptimisation::Skippable).to receive(:new).and_return(skippable)
      end

      it "stores component state" do
        expect(Datadog::CI::Utils::FileStorage).to receive(:store).with(
          described_class::FILE_STORAGE_KEY,
          {
            correlation_id: "42",
            skippable_tests: Set.new(["suite.test.", "suite.test2."])
          }
        ).and_return(true)

        configure
      end
    end

    context "when test session is not distributed" do
      let(:tests_skipping_enabled) { true }
      let(:skippable_response) do
        instance_double(
          Datadog::CI::TestOptimisation::Skippable::Response,
          correlation_id: "42",
          tests: Set.new(["suite.test.", "suite.test2."]),
          ok?: true
        )
      end
      let(:skippable) do
        instance_double(
          Datadog::CI::TestOptimisation::Skippable,
          fetch_skippable_tests: skippable_response
        )
      end

      before do
        allow(test_session).to receive(:distributed).and_return(false)
        allow(Datadog::CI::TestOptimisation::Skippable).to receive(:new).and_return(skippable)
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
        allow(Datadog::CI::TestOptimisation::Skippable).to receive(:new)
      end

      context "when component state exists in file storage" do
        let(:stored_correlation_id) { "stored_correlation_id" }
        let(:stored_skippable_tests) { Set.new(["stored.test1.", "stored.test2."]) }
        let(:stored_state) { {correlation_id: stored_correlation_id, skippable_tests: stored_skippable_tests} }

        before do
          allow(Datadog::CI::Utils::FileStorage).to receive(:retrieve)
            .with(described_class::FILE_STORAGE_KEY)
            .and_return(stored_state)
        end

        it "loads component state from file storage" do
          configure

          expect(component.correlation_id).to eq(stored_correlation_id)
          expect(component.skippable_tests).to eq(stored_skippable_tests)
          expect(Datadog::CI::TestOptimisation::Skippable).not_to have_received(:new)
        end
      end

      context "when component state does not exist in file storage" do
        let(:skippable) do
          instance_double(
            Datadog::CI::TestOptimisation::Skippable,
            fetch_skippable_tests: instance_double(
              Datadog::CI::TestOptimisation::Skippable::Response,
              correlation_id: "42",
              tests: Set.new(["suite.test.", "suite.test2."]),
              ok?: true
            )
          )
        end

        before do
          allow(Datadog::CI::Utils::FileStorage).to receive(:retrieve)
            .with(described_class::FILE_STORAGE_KEY)
            .and_return(nil)
          allow(Datadog::CI::TestOptimisation::Skippable).to receive(:new).and_return(skippable)
        end

        it "fetches skippable tests" do
          expect(Datadog::CI::TestOptimisation::Skippable).to receive(:new).and_return(skippable)

          configure

          expect(component.correlation_id).to eq("42")
          expect(component.skippable_tests).to eq(Set.new(["suite.test.", "suite.test2."]))
        end
      end
    end

    context "when skippable_tests.json file from Datadog Test Runner exists" do
      let(:tests_skipping_enabled) { true }
      let(:skippable_tests_file_path) { ".dd/context/skippable_tests.json" }

      before do
        # Create .dd/context folder if it doesn't exist
        FileUtils.mkdir_p(".dd/context")

        # Write skippable tests data to the file
        File.write(skippable_tests_file_path, JSON.pretty_generate(skippable_tests_data))

        # Ensure no state in file storage
        allow(Datadog::CI::Utils::FileStorage).to receive(:retrieve)
          .with(described_class::FILE_STORAGE_KEY)
          .and_return(nil)
      end

      after do
        FileUtils.rm_rf(".dd")
      end

      context "and contains valid data" do
        let(:skippable_tests_data) do
          {
            "correlationId" => "ff290c827effa555f26e890267cf5e63",
            "skippableTests" => {
              " at ./spec/requests/articles/org_redirect_spec.rb" => {
                "does not infinitely redirect" => [
                  {
                    "suite" => " at ./spec/requests/articles/org_redirect_spec.rb",
                    "name" => "does not infinitely redirect",
                    "parameters" => "{\"arguments\":{},\"metadata\":{\"scoped_id\":\"1:1\"}}",
                    "configurations" => {}
                  }
                ]
              },
              "AdminControllerTest" => {
                "test_index" => [
                  {
                    "suite" => "AdminControllerTest",
                    "name" => "test_index",
                    "parameters" => "{\"arguments\":{}}",
                    "configurations" => {}
                  }
                ]
              }
            }
          }
        end

        it "loads skippable tests from the file" do
          configure

          expect(component.correlation_id).to eq("ff290c827effa555f26e890267cf5e63")
          expect(component.skippable_tests.size).to eq(2)
          expect(component.skippable_tests).to include(" at ./spec/requests/articles/org_redirect_spec.rb.does not infinitely redirect.{\"arguments\":{},\"metadata\":{\"scoped_id\":\"1:1\"}}")
          expect(component.skippable_tests).to include("AdminControllerTest.test_index.{\"arguments\":{}}")
        end

        it "enables test optimization functionality" do
          configure

          expect(component.enabled?).to be true
          expect(component.skipping_tests?).to be true
        end

        it "does not call skippable tests API" do
          expect(Datadog::CI::TestOptimisation::Skippable).not_to receive(:new)

          configure
        end
      end

      context "when skippable_tests.json file contains empty skippableTests" do
        let(:skippable_tests_data) do
          {
            "correlationId" => "empty123",
            "skippableTests" => {}
          }
        end

        it "loads empty skippable tests" do
          configure

          expect(component.correlation_id).to eq("empty123")
          expect(component.skippable_tests).to be_empty
          expect(component.enabled?).to be true
          expect(component.skipping_tests?).to be true
        end
      end
    end

    context "when ITR is disabled locally" do
      let(:local_itr_enabled) { false }

      it "does not use remote configuration" do
        configure

        expect(component.enabled?).to be false
        expect(component.skipping_tests?).to be false
        expect(component.code_coverage?).to be false
      end
    end
  end

  describe "#start_coverage" do
    subject { component.start_coverage(test_span) }

    let(:test_tracer_span) { Datadog::Tracing::SpanOperation.new("test") }
    let(:test_span) { Datadog::CI::Test.new(tracer_span) }

    before do
      configure
    end

    context "when code coverage is disabled" do
      let(:code_coverage_enabled) { false }
      let(:tests_skipping_enabled) { false }

      it "does not start coverage" do
        expect(component).not_to receive(:coverage_collector)

        subject
        expect(component.stop_coverage(test_span)).to be_nil
      end
    end

    context "when TestOptimisation is disabled" do
      let(:itr_enabled) { false }
      let(:code_coverage_enabled) { false }
      let(:tests_skipping_enabled) { false }

      it "does not start coverage" do
        expect(component).not_to receive(:coverage_collector)

        subject
        expect(component.stop_coverage(test_span)).to be_nil
      end
    end

    context "when code coverage is enabled" do
      let(:tests_skipping_enabled) { false }

      before do
        skip("Code coverage is not supported in JRuby") if PlatformHelpers.jruby?
      end

      it "starts coverage" do
        expect(component).to receive(:coverage_collector).twice.and_call_original

        subject
        expect(1 + 1).to eq(2)
        coverage_event = component.stop_coverage(test_span)
        expect(coverage_event.coverage.size).to be > 0
      end

      it_behaves_like "emits telemetry metric", :inc, Datadog::CI::Ext::Telemetry::METRIC_CODE_COVERAGE_STARTED, 1
    end

    context "when JRuby and code coverage is enabled" do
      let(:tests_skipping_enabled) { false }

      before do
        skip("Skipped for CRuby") unless PlatformHelpers.jruby?
      end

      it "disables code coverage" do
        expect(component).not_to receive(:coverage_collector)
        expect(component.code_coverage?).to be(false)

        component.start_coverage(test_span)
        expect(component.stop_coverage(test_span)).to be_nil
      end
    end
  end

  describe "#stop_coverage" do
    subject { component.stop_coverage(test_span) }

    let(:test_tracer_span) { Datadog::Tracing::SpanOperation.new("test") }
    let(:test_span) { Datadog::CI::Test.new(tracer_span) }
    let(:tests_skipping_enabled) { false }

    before do
      skip("Code coverage is not supported in JRuby") if PlatformHelpers.jruby?

      configure

      allow(test_span).to receive(:id).and_return(1)
      allow(test_span).to receive(:test_suite_id).and_return(2)
      allow(test_span).to receive(:test_session_id).and_return(3)
    end

    context "when coverage was collected" do
      before do
        component.start_coverage(test_span)
        expect(1 + 1).to eq(2)
      end

      it "creates coverage event and writes it" do
        expect(subject).not_to be_nil

        expect(writer).to have_received(:write) do |event|
          expect(event.test_id).to eq("1")
          expect(event.test_suite_id).to eq("2")
          expect(event.test_session_id).to eq("3")

          expect(event.coverage.size).to be > 0
        end
      end

      it_behaves_like "emits telemetry metric", :inc, Datadog::CI::Ext::Telemetry::METRIC_CODE_COVERAGE_FINISHED, 1
      it_behaves_like "emits telemetry metric", :distribution, Datadog::CI::Ext::Telemetry::METRIC_CODE_COVERAGE_FILES, 5.0
    end

    context "when test is skipped" do
      before do
        component.start_coverage(test_span)
        expect(1 + 1).to eq(2)
        test_span.skipped!
      end

      it "does not write coverage event" do
        expect(subject).to be_nil
        expect(writer).not_to have_received(:write)
      end

      it_behaves_like "emits no metric", :inc, Datadog::CI::Ext::Telemetry::METRIC_CODE_COVERAGE_IS_EMPTY
    end

    context "when test is skipped and coverage is not collected" do
      before do
        test_span.skipped!
      end

      it "does not write coverage event" do
        expect(subject).to be_nil
        expect(writer).not_to have_received(:write)
      end

      it_behaves_like "emits no metric", :inc, Datadog::CI::Ext::Telemetry::METRIC_CODE_COVERAGE_IS_EMPTY
    end

    context "when coverage was not collected" do
      it "does not write coverage event" do
        expect(1 + 1).to eq(2)

        expect(subject).to be_nil
        expect(writer).not_to have_received(:write)
      end

      it_behaves_like "emits telemetry metric", :inc, Datadog::CI::Ext::Telemetry::METRIC_CODE_COVERAGE_IS_EMPTY, 1
    end
  end

  describe "#mark_if_skippable" do
    subject { component.mark_if_skippable(test_span) }

    context "when skipping tests" do
      let(:skippable) do
        instance_double(
          Datadog::CI::TestOptimisation::Skippable,
          fetch_skippable_tests: instance_double(
            Datadog::CI::TestOptimisation::Skippable::Response,
            correlation_id: "42",
            tests: Set.new(["suite.test.", "suite2.test.", "suite.test3."]),
            ok?: true
          )
        )
      end

      before do
        expect(Datadog::CI::TestOptimisation::Skippable).to receive(:new).and_return(skippable)

        configure
      end

      context "when test is skippable" do
        let(:test_span) do
          Datadog::CI::Test.new(
            Datadog::Tracing::SpanOperation.new("test", tags: {"test.name" => "test", "test.suite" => "suite"})
          )
        end

        it "marks test as skippable" do
          expect { subject }
            .to change { test_span.skipped_by_test_impact_analysis? }
            .from(false)
            .to(true)
        end
      end

      context "when test is not skippable" do
        let(:test_span) do
          Datadog::CI::Test.new(
            Datadog::Tracing::SpanOperation.new("test", tags: {"test.name" => "test2", "test.suite" => "suite"})
          )
        end

        it "does not mark test as skippable" do
          expect { subject }
            .not_to change { test_span.skipped_by_test_impact_analysis? }
        end
      end
    end

    context "when not skipping tests" do
      let(:tests_skipping_enabled) { false }

      before do
        configure
      end

      let(:test_span) do
        Datadog::CI::Test.new(
          Datadog::Tracing::SpanOperation.new("test", tags: {"test.name" => "test", "test.suite" => "suite"})
        )
      end

      it "does not mark test as skippable" do
        expect { subject }
          .not_to change { test_span.skipped_by_test_impact_analysis? }
      end
    end
  end

  describe "#on_test_finished" do
    subject { component.on_test_finished(test_span, testvis_context) }

    let(:testvis_context) do
      spy(Datadog::CI::TestVisibility::Context)
    end

    context "test is skipped by framework" do
      let(:test_span) do
        Datadog::CI::Test.new(
          Datadog::Tracing::SpanOperation.new("test", tags: {"test.status" => "skip"})
        )
      end

      it "does not increment skipped tests count" do
        subject

        expect(testvis_context).not_to have_received(:incr_tests_skipped_by_tia_count)
      end

      it_behaves_like "emits no metric", :inc, Datadog::CI::Ext::Telemetry::METRIC_ITR_SKIPPED
    end

    context "test is skipped by ITR" do
      let(:test_span) do
        Datadog::CI::Test.new(
          Datadog::Tracing::SpanOperation.new("test", tags: {"test.status" => "skip", "test.skipped_by_itr" => "true"})
        )
      end

      it "increments skipped tests count" do
        subject

        expect(testvis_context).to have_received(:incr_tests_skipped_by_tia_count)
      end

      it_behaves_like "emits telemetry metric", :inc, Datadog::CI::Ext::Telemetry::METRIC_ITR_SKIPPED, 1
    end

    context "test is not skipped" do
      let(:test_span) do
        Datadog::CI::Test.new(
          Datadog::Tracing::SpanOperation.new("test")
        )
      end

      it "does not increment skipped tests count" do
        subject

        expect(testvis_context).not_to have_received(:incr_tests_skipped_by_tia_count)
      end

      it_behaves_like "emits no metric", :inc, Datadog::CI::Ext::Telemetry::METRIC_ITR_SKIPPED
    end
  end

  describe "#write_test_session_tags" do
    let(:test_session_span) do
      Datadog::CI::TestSession.new(
        Datadog::Tracing::SpanOperation.new("test_session")
      )
    end

    subject { component.write_test_session_tags(test_session_span, skipped_tests_count) }
    let(:skipped_tests_count) { 0 }

    context "when ITR is enabled" do
      context "when tests were not skipped" do
        let(:skipped_tests_count) { 0 }

        it "submits 0 skipped tests" do
          subject

          expect(test_session_span.get_tag(Datadog::CI::Ext::Test::TAG_ITR_TESTS_SKIPPED)).to eq("false")
          expect(test_session_span.get_tag(Datadog::CI::Ext::Test::TAG_ITR_TEST_SKIPPING_COUNT)).to eq(0)
        end
      end

      context "when tests were skipped" do
        let(:skipped_tests_count) { 1 }

        it "submits number of skipped tests" do
          subject

          expect(test_session_span.get_tag(Datadog::CI::Ext::Test::TAG_ITR_TESTS_SKIPPED)).to eq("true")
          expect(test_session_span.get_tag(Datadog::CI::Ext::Test::TAG_ITR_TEST_SKIPPING_COUNT)).to eq(1)
        end
      end
    end

    context "when TestOptimisation is disabled" do
      let(:local_itr_enabled) { false }

      it "does not add ITR/TestOptimisation tags to the session" do
        subject

        expect(test_session_span.get_tag(Datadog::CI::Ext::Test::TAG_ITR_TESTS_SKIPPED)).to be_nil
        expect(test_session_span.get_tag(Datadog::CI::Ext::Test::TAG_ITR_TEST_SKIPPING_COUNT)).to be_nil
      end
    end
  end
end
