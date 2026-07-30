# frozen_string_literal: true

RSpec.describe Datadog::CI::TestSuite do
  let(:test_suite_name) { "my.suite" }
  let(:tracer_span) { instance_double(Datadog::Tracing::SpanOperation, finish: true, name: test_suite_name) }
  let(:test_tracing) { spy("test_tracing") }

  before { allow_any_instance_of(described_class).to receive(:test_tracing).and_return(test_tracing) }
  subject(:ci_test_suite) { described_class.new(tracer_span) }

  describe "impacted files" do
    it "adds unique paths incrementally and returns an immutable snapshot" do
      ci_test_suite.add_impacted_files(["app/frontend/shared.js", "app/frontend/shared.js"])
      snapshot = ci_test_suite.impacted_files
      ci_test_suite.add_impacted_files(["app/frontend/shared.js", "app/frontend/setup.js"])

      expect(snapshot).to eq(["app/frontend/shared.js"])
      expect(snapshot).to be_frozen
      expect(ci_test_suite.impacted_files).to eq(
        ["app/frontend/shared.js", "app/frontend/setup.js"]
      )
    end

    it "clears impacted files" do
      ci_test_suite.add_impacted_files(["app/frontend/shared.js"])

      ci_test_suite.clear_impacted_files

      expect(ci_test_suite.impacted_files).to be_empty
    end

    it "rejects non-array collections" do
      expect { ci_test_suite.add_impacted_files(Set.new(["app/frontend/shared.js"])) }
        .to raise_error(ArgumentError, "file_paths must be an Array")
    end

    it "keeps the first 10,000 unique paths and warns" do
      allow(Datadog.logger).to receive(:warn)
      files = Array.new(described_class::MAX_IMPACTED_FILES + 1) do |index|
        "app/frontend/file-#{index}.js"
      end

      ci_test_suite.add_impacted_files(files)

      expect(ci_test_suite.impacted_files).to eq(files.first(described_class::MAX_IMPACTED_FILES))
      expect(Datadog.logger).to have_received(:warn).once.with(
        "Test Impact Analysis supports at most 10000 impacted files per test suite; " \
        "additional files will be ignored"
      )
    end
  end

  describe "#should_skip?" do
    it "returns true when the suite was skipped by Test Impact Analysis" do
      allow(tracer_span).to receive(:get_tag)
        .with(Datadog::CI::Ext::Test::TAG_ITR_SKIPPED_BY_ITR)
        .and_return("true")

      expect(ci_test_suite.should_skip?).to be true
    end

    it "returns false otherwise" do
      allow(tracer_span).to receive(:get_tag)
        .with(Datadog::CI::Ext::Test::TAG_ITR_SKIPPED_BY_ITR)
        .and_return(nil)

      expect(ci_test_suite.should_skip?).to be false
    end
  end

  describe "#datadog_skip_reason" do
    it "returns the suite skip reason tag" do
      allow(tracer_span).to receive(:get_tag)
        .with(Datadog::CI::Ext::Test::TAG_SKIP_REASON)
        .and_return(Datadog::CI::Ext::Test::SkipReason::TEST_IMPACT_ANALYSIS)

      expect(ci_test_suite.datadog_skip_reason).to eq(Datadog::CI::Ext::Test::SkipReason::TEST_IMPACT_ANALYSIS)
    end
  end

  describe "#finish" do
    subject(:finish) { ci_test_suite.finish }

    before do
      expect(tracer_span).to receive(:get_tag).with(Datadog::CI::Ext::Test::TAG_STATUS).and_return(
        test_suite_status
      )
    end

    context "when test suite has status" do
      let(:test_suite_status) { Datadog::CI::Ext::Test::Status::PASS }

      it "deactivates the test suite" do
        finish

        expect(test_tracing).to have_received(:deactivate_test_suite).with(test_suite_name)
      end
    end

    context "when test suite has no status" do
      let(:test_suite_status) { nil }

      context "and there are test failures" do
        before do
          ci_test_suite.record_test_final_status("t1", Datadog::CI::Ext::Test::Status::PASS)
          ci_test_suite.record_test_final_status("t2", Datadog::CI::Ext::Test::Status::SKIP)
          ci_test_suite.record_test_final_status("t3", Datadog::CI::Ext::Test::Status::FAIL)
        end

        it "sets the status to fail" do
          expect(tracer_span).to receive(:set_tag).with(
            Datadog::CI::Ext::Test::TAG_STATUS, Datadog::CI::Ext::Test::Status::FAIL
          )
          expect(tracer_span).to receive(:status=).with(1)

          finish

          expect(test_tracing).to have_received(:deactivate_test_suite).with(test_suite_name)
        end
      end

      context "and there are only skipped tests" do
        before do
          ci_test_suite.record_test_final_status("t1", Datadog::CI::Ext::Test::Status::SKIP)
          ci_test_suite.record_test_final_status("t2", Datadog::CI::Ext::Test::Status::SKIP)
          ci_test_suite.record_test_final_status("t3", Datadog::CI::Ext::Test::Status::SKIP)
        end

        it "sets the status to skip" do
          expect(tracer_span).to receive(:set_tag).with(
            Datadog::CI::Ext::Test::TAG_STATUS, Datadog::CI::Ext::Test::Status::SKIP
          )

          finish

          expect(test_tracing).to have_received(:deactivate_test_suite).with(test_suite_name)
        end
      end

      context "and there are some passed tests" do
        before do
          ci_test_suite.record_test_final_status("t0", Datadog::CI::Ext::Test::Status::SKIP)
          ci_test_suite.record_test_final_status("t1", Datadog::CI::Ext::Test::Status::SKIP)
          ci_test_suite.record_test_final_status("t2", Datadog::CI::Ext::Test::Status::PASS)
        end

        it "sets the status to pass" do
          expect(tracer_span).to receive(:set_tag).with(
            Datadog::CI::Ext::Test::TAG_STATUS, Datadog::CI::Ext::Test::Status::PASS
          )

          finish

          expect(test_tracing).to have_received(:deactivate_test_suite).with(test_suite_name)
        end
      end

      context "some tests were retried and succeeeded on retries" do
        before do
          # Final status is computed by the test itself, so we just record the final status
          ci_test_suite.record_test_final_status("t1", Datadog::CI::Ext::Test::Status::PASS)
          ci_test_suite.record_test_final_status("t2", Datadog::CI::Ext::Test::Status::SKIP)
        end

        it "sets the status to pass" do
          expect(tracer_span).to receive(:set_tag).with(
            Datadog::CI::Ext::Test::TAG_STATUS, Datadog::CI::Ext::Test::Status::PASS
          )

          finish

          expect(test_tracing).to have_received(:deactivate_test_suite).with(test_suite_name)
        end
      end
    end
  end

  describe "#any_passed?" do
    subject { ci_test_suite.any_passed? }

    context "when there are no tests" do
      it { is_expected.to be false }
    end

    context "when there are tests that are skipped or failed" do
      before do
        ci_test_suite.record_test_result("t1", Datadog::CI::Ext::Test::Status::FAIL)
        ci_test_suite.record_test_result("t2", Datadog::CI::Ext::Test::Status::SKIP)
        ci_test_suite.record_test_result("t3", Datadog::CI::Ext::Test::Status::SKIP)
      end

      it { is_expected.to be false }
    end

    context "when there are passed tests" do
      before do
        ci_test_suite.record_test_result("t1", Datadog::CI::Ext::Test::Status::FAIL)
        ci_test_suite.record_test_result("t2", Datadog::CI::Ext::Test::Status::PASS)
        ci_test_suite.record_test_result("t3", Datadog::CI::Ext::Test::Status::SKIP)
      end

      it { is_expected.to be true }
    end

    context "when test is passed after retry" do
      before do
        ci_test_suite.record_test_result("t1", Datadog::CI::Ext::Test::Status::FAIL)
        ci_test_suite.record_test_result("t1", Datadog::CI::Ext::Test::Status::PASS)
        ci_test_suite.record_test_result("t2", Datadog::CI::Ext::Test::Status::SKIP)
      end

      it { is_expected.to be true }
    end
  end

  describe "#test_executed?" do
    let(:test_id) { "t1" }
    subject { ci_test_suite.test_executed?(test_id) }

    context "when there are no tests" do
      it { is_expected.to be false }
    end

    context "when there are some tests with different ids" do
      before do
        ci_test_suite.record_test_result("t2", Datadog::CI::Ext::Test::Status::SKIP)
        ci_test_suite.record_test_result("t3", Datadog::CI::Ext::Test::Status::SKIP)
      end

      it { is_expected.to be false }
    end

    context "when this test was executed already" do
      before do
        ci_test_suite.record_test_result("t1", Datadog::CI::Ext::Test::Status::FAIL)
      end

      it { is_expected.to be true }
    end
  end
end
