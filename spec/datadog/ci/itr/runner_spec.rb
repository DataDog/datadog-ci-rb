# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/itr/runner"

RSpec.describe Datadog::CI::ITR::Runner do
  let(:itr_enabled) { true }

  let(:api) { double("api") }
  let(:writer) { spy("writer") }
  let(:git_worker) { spy("git_worker") }

  let(:tracer_span) { Datadog::Tracing::SpanOperation.new("session") }
  let(:test_session) { Datadog::CI::TestSession.new(tracer_span) }

  subject(:runner) { described_class.new(api: api, dd_env: "dd_env", coverage_writer: writer, enabled: itr_enabled) }
  let(:configure) { runner.configure(remote_configuration, test_session: test_session, git_tree_upload_worker: git_worker) }

  before do
    allow(writer).to receive(:write)
  end

  describe "#configure" do
    context "when remote configuration call failed" do
      let(:remote_configuration) { {"itr_enabled" => false} }

      it "configures the runner and test session" do
        configure

        expect(runner.enabled?).to be false
        expect(runner.skipping_tests?).to be false
        expect(runner.code_coverage?).to be false
      end
    end

    context "when remote configuration call returned correct response without tests skipping" do
      let(:remote_configuration) { {"itr_enabled" => true, "code_coverage" => true, "tests_skipping" => false} }

      before do
        configure
      end

      it "configures the runner" do
        expect(runner.enabled?).to be true
        expect(runner.skipping_tests?).to be false
        expect(runner.code_coverage?).to be(!PlatformHelpers.jruby?) # code coverage is not supported in JRuby
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
      let(:remote_configuration) { {"itr_enabled" => true, "code_coverage" => true, "tests_skipping" => true} }
      let(:skippable) do
        instance_double(
          Datadog::CI::ITR::Skippable,
          fetch_skippable_tests: instance_double(
            Datadog::CI::ITR::Skippable::Response,
            correlation_id: "42",
            tests: Set.new(["suite.test"])
          )
        )
      end

      before do
        expect(Datadog::CI::ITR::Skippable).to receive(:new).and_return(skippable)
        configure
      end

      it "configures the runner" do
        expect(runner.enabled?).to be true
        expect(runner.skipping_tests?).to be true

        expect(runner.correlation_id).to eq("42")
        expect(runner.skippable_tests).to eq(Set.new(["suite.test"]))

        expect(git_worker).to have_received(:wait_until_done)
      end
    end

    context "when remote configuration call returned correct response with strings instead of bools" do
      let(:remote_configuration) { {"itr_enabled" => "true", "code_coverage" => "true", "tests_skipping" => "false"} }

      it "configures the runner" do
        configure

        expect(runner.enabled?).to be true
        expect(runner.skipping_tests?).to be false
        expect(runner.code_coverage?).to be(!PlatformHelpers.jruby?) # code coverage is not supported in JRuby
      end
    end

    context "when remote configuration call returns empty hash" do
      let(:remote_configuration) { {} }

      it "configures the runner" do
        configure

        expect(runner.enabled?).to be false
        expect(runner.skipping_tests?).to be false
        expect(runner.code_coverage?).to be false
      end
    end
  end

  describe "#start_coverage" do
    let(:test_tracer_span) { Datadog::Tracing::SpanOperation.new("test") }
    let(:test_span) { Datadog::CI::Test.new(tracer_span) }

    before do
      configure
    end

    context "when code coverage is disabled" do
      let(:remote_configuration) { {"itr_enabled" => true, "code_coverage" => false, "tests_skipping" => false} }

      it "does not start coverage" do
        expect(runner).not_to receive(:coverage_collector)

        runner.start_coverage(test_span)
        expect(runner.stop_coverage(test_span)).to be_nil
      end
    end

    context "when ITR is disabled" do
      let(:remote_configuration) { {"itr_enabled" => false, "code_coverage" => false, "tests_skipping" => false} }

      it "does not start coverage" do
        expect(runner).not_to receive(:coverage_collector)

        runner.start_coverage(test_span)
        expect(runner.stop_coverage(test_span)).to be_nil
      end
    end

    context "when code coverage is enabled" do
      let(:remote_configuration) { {"itr_enabled" => true, "code_coverage" => true, "tests_skipping" => false} }

      before do
        skip("Code coverage is not supported in JRuby") if PlatformHelpers.jruby?
      end

      it "starts coverage" do
        expect(runner).to receive(:coverage_collector).twice.and_call_original

        runner.start_coverage(test_span)
        expect(1 + 1).to eq(2)
        coverage_event = runner.stop_coverage(test_span)
        expect(coverage_event.coverage.size).to be > 0
      end
    end

    context "when JRuby and code coverage is enabled" do
      let(:remote_configuration) { {"itr_enabled" => true, "code_coverage" => true, "tests_skipping" => false} }

      before do
        skip("Skipped for CRuby") unless PlatformHelpers.jruby?
      end

      it "disables code coverage" do
        expect(runner).not_to receive(:coverage_collector)
        expect(runner.code_coverage?).to be(false)

        runner.start_coverage(test_span)
        expect(runner.stop_coverage(test_span)).to be_nil
      end
    end
  end

  describe "#stop_coverage" do
    let(:test_tracer_span) { Datadog::Tracing::SpanOperation.new("test") }
    let(:test_span) { Datadog::CI::Test.new(tracer_span) }
    let(:remote_configuration) { {"itr_enabled" => true, "code_coverage" => true, "tests_skipping" => false} }

    before do
      skip("Code coverage is not supported in JRuby") if PlatformHelpers.jruby?

      configure

      allow(test_span).to receive(:id).and_return(1)
      allow(test_span).to receive(:test_suite_id).and_return(2)
      allow(test_span).to receive(:test_session_id).and_return(3)
    end

    it "creates coverage event and writes it" do
      runner.start_coverage(test_span)
      expect(1 + 1).to eq(2)
      expect(runner.stop_coverage(test_span)).not_to be_nil

      expect(writer).to have_received(:write) do |event|
        expect(event.test_id).to eq("1")
        expect(event.test_suite_id).to eq("2")
        expect(event.test_session_id).to eq("3")

        expect(event.coverage.size).to be > 0
      end
    end

    context "when test is skipped" do
      it "does not write coverage event" do
        runner.start_coverage(test_span)
        expect(1 + 1).to eq(2)
        test_span.skipped!

        expect(runner.stop_coverage(test_span)).to be_nil
        expect(writer).not_to have_received(:write)
      end
    end

    context "when coverage was not collected" do
      it "does not write coverage event" do
        expect(1 + 1).to eq(2)

        expect(runner.stop_coverage(test_span)).to be_nil
        expect(writer).not_to have_received(:write)
      end
    end
  end

  describe "#mark_if_skippable" do
    subject { runner.mark_if_skippable(test_span) }

    context "when skipping tests" do
      let(:remote_configuration) { {"itr_enabled" => true, "code_coverage" => true, "tests_skipping" => true} }
      let(:skippable) do
        instance_double(
          Datadog::CI::ITR::Skippable,
          fetch_skippable_tests: instance_double(
            Datadog::CI::ITR::Skippable::Response,
            correlation_id: "42",
            tests: Set.new(["suite.test", "suite2.test", "suite.test3"])
          )
        )
      end

      before do
        expect(Datadog::CI::ITR::Skippable).to receive(:new).and_return(skippable)

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
            .to change { test_span.skipped_by_itr? }
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
            .not_to change { test_span.skipped_by_itr? }
        end
      end
    end

    context "when not skipping tests" do
      let(:remote_configuration) { {"itr_enabled" => true, "code_coverage" => true, "tests_skipping" => false} }

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
          .not_to change { test_span.skipped_by_itr? }
      end
    end
  end

  describe "#count_skipped_test" do
    subject { runner.count_skipped_test(test_span) }

    context "test is skipped by framework" do
      let(:test_span) do
        Datadog::CI::Test.new(
          Datadog::Tracing::SpanOperation.new("test", tags: {"test.status" => "skip"})
        )
      end

      it "does not increment skipped tests count" do
        expect { subject }
          .not_to change { runner.skipped_tests_count }
      end
    end

    context "test is skipped by ITR" do
      let(:test_span) do
        Datadog::CI::Test.new(
          Datadog::Tracing::SpanOperation.new("test", tags: {"test.status" => "skip", "test.itr.skipped_by_itr" => "true"})
        )
      end

      it "increments skipped tests count" do
        expect { subject }
          .to change { runner.skipped_tests_count }
          .from(0)
          .to(1)
      end
    end

    context "test is not skipped" do
      let(:test_span) do
        Datadog::CI::Test.new(
          Datadog::Tracing::SpanOperation.new("test")
        )
      end

      it "does not increment skipped tests count" do
        expect { subject }
          .not_to change { runner.skipped_tests_count }
      end
    end
  end

  describe "#write_test_session_tags" do
    let(:test_session_span) do
      Datadog::CI::TestSession.new(
        Datadog::Tracing::SpanOperation.new("test_session")
      )
    end

    before do
      runner.count_skipped_test(test_span)
    end

    subject { runner.write_test_session_tags(test_session_span) }

    let(:test_span) do
      Datadog::CI::Test.new(
        Datadog::Tracing::SpanOperation.new("test", tags: {"test.status" => "pass"})
      )
    end

    context "when ITR is enabled" do
      context "when tests were not skipped" do
        it "submits 0 skipped tests" do
          subject

          expect(test_session_span.get_tag(Datadog::CI::Ext::Test::TAG_ITR_TESTS_SKIPPED)).to eq("false")
          expect(test_session_span.get_tag(Datadog::CI::Ext::Test::TAG_ITR_TEST_SKIPPING_COUNT)).to eq(0)
        end
      end

      context "when tests were skipped" do
        let(:test_span) do
          Datadog::CI::Test.new(
            Datadog::Tracing::SpanOperation.new("test", tags: {"test.status" => "skip", "test.itr.skipped_by_itr" => "true"})
          )
        end

        it "submits number of skipped tests" do
          subject

          expect(test_session_span.get_tag(Datadog::CI::Ext::Test::TAG_ITR_TESTS_SKIPPED)).to eq("true")
          expect(test_session_span.get_tag(Datadog::CI::Ext::Test::TAG_ITR_TEST_SKIPPING_COUNT)).to eq(1)
        end
      end
    end

    context "when ITR is disabled" do
      let(:itr_enabled) { false }

      it "does not add ITR tags to the session" do
        subject

        expect(test_session_span.get_tag(Datadog::CI::Ext::Test::TAG_ITR_TESTS_SKIPPED)).to be_nil
        expect(test_session_span.get_tag(Datadog::CI::Ext::Test::TAG_ITR_TEST_SKIPPING_COUNT)).to be_nil
      end
    end
  end
end
