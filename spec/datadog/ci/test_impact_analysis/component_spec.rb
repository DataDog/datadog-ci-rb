# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/test_impact_analysis/component"

RSpec.describe Datadog::CI::TestImpactAnalysis::Component do
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
          Datadog::CI::TestImpactAnalysis::Skippable,
          fetch_skippable_tests: instance_double(
            Datadog::CI::TestImpactAnalysis::Skippable::Response,
            correlation_id: "42",
            tests: Set.new(["suite.test.", "suite.test2."]),
            ok?: true
          )
        )
      end

      before do
        expect(Datadog::CI::TestImpactAnalysis::Skippable).to receive(:new).and_return(skippable)

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
          Datadog::CI::TestImpactAnalysis::Skippable::Response,
          correlation_id: "42",
          tests: Set.new(["suite.test.", "suite.test2."]),
          ok?: true
        )
      end
      let(:skippable) do
        instance_double(
          Datadog::CI::TestImpactAnalysis::Skippable,
          fetch_skippable_tests: skippable_response
        )
      end

      before do
        allow(test_session).to receive(:distributed).and_return(true)
        allow(Datadog::CI::TestImpactAnalysis::Skippable).to receive(:new).and_return(skippable)
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
          Datadog::CI::TestImpactAnalysis::Skippable::Response,
          correlation_id: "42",
          tests: Set.new(["suite.test.", "suite.test2."]),
          ok?: true
        )
      end
      let(:skippable) do
        instance_double(
          Datadog::CI::TestImpactAnalysis::Skippable,
          fetch_skippable_tests: skippable_response
        )
      end

      before do
        allow(test_session).to receive(:distributed).and_return(false)
        allow(Datadog::CI::TestImpactAnalysis::Skippable).to receive(:new).and_return(skippable)
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
        allow(Datadog::CI::TestImpactAnalysis::Skippable).to receive(:new)
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
          expect(Datadog::CI::TestImpactAnalysis::Skippable).not_to have_received(:new)
        end
      end

      context "when component state does not exist in file storage" do
        let(:skippable) do
          instance_double(
            Datadog::CI::TestImpactAnalysis::Skippable,
            fetch_skippable_tests: instance_double(
              Datadog::CI::TestImpactAnalysis::Skippable::Response,
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
          allow(Datadog::CI::TestImpactAnalysis::Skippable).to receive(:new).and_return(skippable)
        end

        it "fetches skippable tests" do
          expect(Datadog::CI::TestImpactAnalysis::Skippable).to receive(:new).and_return(skippable)

          configure

          expect(component.correlation_id).to eq("42")
          expect(component.skippable_tests).to eq(Set.new(["suite.test.", "suite.test2."]))
        end
      end
    end

    context "when skippable_tests.json file from DDTest exists" do
      let(:tests_skipping_enabled) { true }
      let(:skippable_tests_file_path) { "#{Datadog::CI::Ext::DDTest::TESTOPTIMIZATION_CACHE_PATH}/skippable_tests.json" }

      before do
        # Create #{Datadog::CI::Ext::DDTest::TESTOPTIMIZATION_CACHE_PATH} folder if it doesn't exist
        FileUtils.mkdir_p(Datadog::CI::Ext::DDTest::TESTOPTIMIZATION_CACHE_PATH)

        # Write skippable tests data to the file
        File.write(skippable_tests_file_path, JSON.pretty_generate(skippable_tests_data))

        # Ensure no state in file storage
        allow(Datadog::CI::Utils::FileStorage).to receive(:retrieve)
          .with(described_class::FILE_STORAGE_KEY)
          .and_return(nil)
      end

      after do
        FileUtils.rm_rf(Datadog::CI::Ext::DDTest::PLAN_FOLDER)
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
          expect(Datadog::CI::TestImpactAnalysis::Skippable).not_to receive(:new)

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

  describe "#start_coverage and #stop_coverage (low-level)" do
    before do
      configure
    end

    context "when code coverage is disabled" do
      let(:code_coverage_enabled) { false }
      let(:tests_skipping_enabled) { false }

      it "does not start coverage" do
        expect(component).not_to receive(:coverage_collector)

        component.start_coverage
        expect(component.stop_coverage).to be_nil
      end
    end

    context "when TestImpactAnalysis is disabled" do
      let(:itr_enabled) { false }
      let(:code_coverage_enabled) { false }
      let(:tests_skipping_enabled) { false }

      it "does not start coverage" do
        expect(component).not_to receive(:coverage_collector)

        component.start_coverage
        expect(component.stop_coverage).to be_nil
      end
    end

    context "when code coverage is enabled" do
      let(:tests_skipping_enabled) { false }

      before do
        skip("Code coverage is not supported in JRuby") if PlatformHelpers.jruby?
      end

      it "starts and stops coverage, returning raw coverage hash" do
        expect(component).to receive(:coverage_collector).twice.and_call_original

        component.start_coverage
        expect(1 + 1).to eq(2)
        coverage = component.stop_coverage

        # stop_coverage now returns raw coverage hash, not an event
        expect(coverage).to be_a(Hash)
        expect(coverage.size).to be > 0
      end
    end

    context "when JRuby and code coverage is enabled" do
      let(:tests_skipping_enabled) { false }

      before do
        skip("Skipped for CRuby") unless PlatformHelpers.jruby?
      end

      it "disables code coverage" do
        expect(component).not_to receive(:coverage_collector)
        expect(component.code_coverage?).to be(false)

        component.start_coverage
        expect(component.stop_coverage).to be_nil
      end
    end
  end

  describe "#on_test_finished (full lifecycle with event writing and ITR stats)" do
    let(:test_tracer_span) { Datadog::Tracing::SpanOperation.new("test") }
    let(:test_span) { Datadog::CI::Test.new(test_tracer_span) }
    let(:tests_skipping_enabled) { false }
    let(:context) { instance_double(Datadog::CI::TestVisibility::Context, incr_tests_skipped_by_tia_count: nil) }

    subject { component.on_test_finished(test_span, context) }

    before do
      skip("Code coverage is not supported in JRuby") if PlatformHelpers.jruby?

      configure

      allow(test_span).to receive(:id).and_return(1)
      allow(test_span).to receive(:test_suite_id).and_return(2)
      allow(test_span).to receive(:test_session_id).and_return(3)

      test_span.context_ids = []
    end

    context "when coverage was collected" do
      before do
        component.on_test_started(test_span)
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
      it_behaves_like "emits telemetry metric", :distribution, Datadog::CI::Ext::Telemetry::METRIC_CODE_COVERAGE_FILES, 6.0
    end

    context "when test is skipped" do
      before do
        component.on_test_started(test_span)
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

  describe "#context_coverage_enabled?" do
    context "when code coverage is enabled and multi-threaded mode" do
      let(:tests_skipping_enabled) { false }

      before do
        skip("Code coverage is not supported in JRuby") if PlatformHelpers.jruby?
        configure
      end

      it "returns true" do
        expect(component.context_coverage_enabled?).to be true
      end
    end

    context "when single-threaded coverage mode is enabled" do
      let(:single_threaded_component) do
        described_class.new(
          api: api,
          dd_env: "dd_env",
          coverage_writer: writer,
          enabled: true,
          use_single_threaded_coverage: true
        )
      end

      let(:tests_skipping_enabled) { false }

      before do
        skip("Code coverage is not supported in JRuby") if PlatformHelpers.jruby?
        single_threaded_component.configure(remote_configuration, test_session)
      end

      it "returns false" do
        expect(single_threaded_component.context_coverage_enabled?).to be false
      end
    end

    context "when code coverage is disabled" do
      let(:code_coverage_enabled) { false }
      let(:tests_skipping_enabled) { false }

      before { configure }

      it "returns false" do
        expect(component.context_coverage_enabled?).to be false
      end
    end
  end

  describe "#on_test_context_started" do
    let(:context_id) { "1:1" }
    let(:tests_skipping_enabled) { false }

    before do
      skip("Code coverage is not supported in JRuby") if PlatformHelpers.jruby?
      configure
    end

    context "when context coverage is enabled (multi-threaded mode)" do
      it "starts coverage collection for the context" do
        expect(component).to receive(:coverage_collector).and_call_original

        component.on_test_context_started(context_id)
      end
    end

    context "when single-threaded coverage mode is enabled" do
      let(:single_threaded_component) do
        described_class.new(
          api: api,
          dd_env: "dd_env",
          coverage_writer: writer,
          enabled: true,
          use_single_threaded_coverage: true
        )
      end

      before do
        single_threaded_component.configure(remote_configuration, test_session)
      end

      it "does not start context coverage collection" do
        expect(single_threaded_component).not_to receive(:coverage_collector)

        single_threaded_component.on_test_context_started(context_id)
      end
    end

    context "when code coverage is disabled" do
      let(:code_coverage_enabled) { false }

      it "does not start context coverage collection" do
        expect(component).not_to receive(:coverage_collector)

        component.on_test_context_started(context_id)
      end
    end
  end

  describe "#on_test_started and #on_test_finished (context coverage integration)" do
    let(:test_tracer_span) { Datadog::Tracing::SpanOperation.new("test") }
    let(:test_span) { Datadog::CI::Test.new(test_tracer_span) }
    let(:tests_skipping_enabled) { false }
    let(:context_ids) { ["1", "1:1"] }
    let(:context) { instance_double(Datadog::CI::TestVisibility::Context, incr_tests_skipped_by_tia_count: nil) }

    before do
      skip("Code coverage is not supported in JRuby") if PlatformHelpers.jruby?
      configure

      allow(test_span).to receive(:id).and_return(1)
      allow(test_span).to receive(:test_suite_id).and_return(2)
      allow(test_span).to receive(:test_session_id).and_return(3)
    end

    context "when context coverage was collected" do
      before do
        # Simulate context coverage collection
        component.on_test_context_started("1")
        # Execute some code to be covered
        expect(1 + 1).to eq(2)
      end

      it "stores context coverage when test starts and merges it when test finishes" do
        # Set context IDs on test span
        test_span.context_ids = context_ids

        # Start test coverage (this stops context coverage and stores it)
        component.on_test_started(test_span)

        # Verify context coverage was stored
        context_coverages = component.instance_variable_get(:@context_coverages)
        expect(context_coverages["1"]).not_to be_nil
        expect(context_coverages["1"].size).to be > 0

        # Execute test code
        expect(2 + 2).to eq(4)

        # Finish test coverage
        event = component.on_test_finished(test_span, context)

        expect(event).not_to be_nil
        expect(event.coverage.size).to be > 0
        expect(writer).to have_received(:write)
      end
    end

    context "when no context coverage was collected" do
      it "creates coverage event with only test coverage" do
        test_span.context_ids = []
        component.on_test_started(test_span)

        # Execute test code
        expect(2 + 2).to eq(4)

        event = component.on_test_finished(test_span, context)

        expect(event).not_to be_nil
        expect(event.coverage.size).to be > 0
        expect(writer).to have_received(:write)
      end
    end

    context "when test is skipped" do
      it "does not write coverage event" do
        test_span.context_ids = []
        component.on_test_started(test_span)
        expect(2 + 2).to eq(4)
        test_span.skipped!

        event = component.on_test_finished(test_span, context)

        expect(event).to be_nil
        expect(writer).not_to have_received(:write)
      end
    end

    context "when single-threaded coverage mode is enabled" do
      let(:single_threaded_component) do
        described_class.new(
          api: api,
          dd_env: "dd_env",
          coverage_writer: writer,
          enabled: true,
          use_single_threaded_coverage: true
        )
      end

      before do
        single_threaded_component.configure(remote_configuration, test_session)
      end

      it "does not merge context coverage but still collects test coverage" do
        # Try to start context coverage (should be skipped)
        single_threaded_component.on_test_context_started("1")
        expect(1 + 1).to eq(2)

        # Set context IDs on test span
        test_span.context_ids = ["1"]

        # Start test coverage
        single_threaded_component.on_test_started(test_span)

        # Execute test code
        expect(2 + 2).to eq(4)

        # Finish test coverage
        event = single_threaded_component.on_test_finished(test_span, context)

        expect(event).not_to be_nil
        # Context coverage should not be stored in single-threaded mode
        context_coverages = single_threaded_component.instance_variable_get(:@context_coverages)
        expect(context_coverages).to be_empty
      end
    end
  end

  describe "#clear_context_coverage" do
    let(:context_id) { "1:1" }
    let(:tests_skipping_enabled) { false }

    before do
      skip("Code coverage is not supported in JRuby") if PlatformHelpers.jruby?
      configure
    end

    context "when context coverage exists" do
      before do
        # Store some context coverage
        component.instance_variable_get(:@context_coverages)[context_id] = {"file.rb" => true}
      end

      it "removes the context coverage" do
        component.clear_context_coverage(context_id)

        context_coverages = component.instance_variable_get(:@context_coverages)
        expect(context_coverages[context_id]).to be_nil
      end
    end

    context "when context coverage does not exist" do
      it "does not raise an error" do
        expect { component.clear_context_coverage(context_id) }.not_to raise_error
      end
    end

    context "when single-threaded coverage mode is enabled" do
      subject(:component) do
        described_class.new(
          api: api,
          dd_env: "dd_env",
          coverage_writer: writer,
          enabled: true,
          use_single_threaded_coverage: true
        )
      end

      it "does nothing" do
        # Should not raise and should not try to access mutex
        expect { component.clear_context_coverage(context_id) }.not_to raise_error
      end
    end
  end

  describe "context coverage merging with multiple contexts" do
    let(:test_tracer_span) { Datadog::Tracing::SpanOperation.new("test") }
    let(:test_span) { Datadog::CI::Test.new(test_tracer_span) }
    let(:tests_skipping_enabled) { false }
    let(:context) { instance_double(Datadog::CI::TestVisibility::Context, incr_tests_skipped_by_tia_count: nil) }

    before do
      skip("Code coverage is not supported in JRuby") if PlatformHelpers.jruby?
      configure

      allow(test_span).to receive(:id).and_return(1)
      allow(test_span).to receive(:test_suite_id).and_return(2)
      allow(test_span).to receive(:test_session_id).and_return(3)
    end

    it "merges coverage from multiple context levels" do
      # Manually set up context coverages to simulate multiple nested contexts
      context_coverages = component.instance_variable_get(:@context_coverages)
      context_coverages["1"] = {"/path/to/outer_context_file.rb" => true}
      context_coverages["1:1"] = {"/path/to/inner_context_file.rb" => true}

      # Set context IDs on test span
      test_span.context_ids = ["1", "1:1"]

      # Start test coverage
      component.on_test_started(test_span)

      # Execute test code
      expect(2 + 2).to eq(4)

      # Finish test coverage
      event = component.on_test_finished(test_span, context)

      expect(event).not_to be_nil
      # Coverage should include files from both contexts
      expect(event.coverage.keys).to include("/path/to/outer_context_file.rb")
      expect(event.coverage.keys).to include("/path/to/inner_context_file.rb")
    end

    it "does not duplicate files already in test coverage" do
      # Set up context coverage with a file
      context_coverages = component.instance_variable_get(:@context_coverages)
      context_coverages["1"] = {"/path/to/shared_file.rb" => true}

      # Set context IDs on test span
      test_span.context_ids = ["1"]

      component.on_test_started(test_span)

      # The coverage collector will collect its own files during test execution
      expect(2 + 2).to eq(4)

      event = component.on_test_finished(test_span, context)

      expect(event).not_to be_nil
      # File from context should be included
      expect(event.coverage.keys).to include("/path/to/shared_file.rb")
    end
  end

  describe "#mark_if_skippable" do
    subject { component.mark_if_skippable(test_span) }

    context "when skipping tests" do
      let(:skippable) do
        instance_double(
          Datadog::CI::TestImpactAnalysis::Skippable,
          fetch_skippable_tests: instance_double(
            Datadog::CI::TestImpactAnalysis::Skippable::Response,
            correlation_id: "42",
            tests: Set.new(["suite.test.", "suite2.test.", "suite.test3."]),
            ok?: true
          )
        )
      end

      before do
        expect(Datadog::CI::TestImpactAnalysis::Skippable).to receive(:new).and_return(skippable)

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

    context "when TestImpactAnalysis is disabled" do
      let(:local_itr_enabled) { false }

      it "does not add ITR/TestImpactAnalysis tags to the session" do
        subject

        expect(test_session_span.get_tag(Datadog::CI::Ext::Test::TAG_ITR_TESTS_SKIPPED)).to be_nil
        expect(test_session_span.get_tag(Datadog::CI::Ext::Test::TAG_ITR_TEST_SKIPPING_COUNT)).to be_nil
      end
    end
  end
end
