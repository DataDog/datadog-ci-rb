# frozen_string_literal: true

RSpec.describe Datadog::CI::TestSuite do
  let(:test_suite_name) { "my.suite" }
  let(:tracer_span) { instance_double(Datadog::Tracing::SpanOperation, finish: true, name: test_suite_name) }
  let(:recorder) { spy("recorder") }

  before { allow_any_instance_of(described_class).to receive(:recorder).and_return(recorder) }
  subject(:ci_test_suite) { described_class.new(tracer_span) }

  describe "#record_test_result" do
    let(:failed_tests_count) { 2 }
    let(:skipped_tests_count) { 3 }
    let(:passed_tests_count) { 5 }

    before do
      failed_tests_count.times do
        ci_test_suite.record_test_result(Datadog::CI::Ext::Test::Status::FAIL)
      end
      skipped_tests_count.times do
        ci_test_suite.record_test_result(Datadog::CI::Ext::Test::Status::SKIP)
      end
      passed_tests_count.times do
        ci_test_suite.record_test_result(Datadog::CI::Ext::Test::Status::PASS)
      end
    end

    it "records the test results" do
      expect(ci_test_suite.failed_tests_count).to eq(failed_tests_count)
      expect(ci_test_suite.skipped_tests_count).to eq(skipped_tests_count)
      expect(ci_test_suite.passed_tests_count).to eq(passed_tests_count)
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

        expect(recorder).to have_received(:deactivate_test_suite).with(test_suite_name)
      end
    end

    context "when test suite has no status" do
      let(:test_suite_status) { nil }

      context "and there are test failures" do
        before do
          ci_test_suite.record_test_result(Datadog::CI::Ext::Test::Status::FAIL)
        end

        it "sets the status to fail" do
          expect(tracer_span).to receive(:set_tag).with(
            Datadog::CI::Ext::Test::TAG_STATUS, Datadog::CI::Ext::Test::Status::FAIL
          )
          expect(tracer_span).to receive(:status=).with(1)

          finish

          expect(recorder).to have_received(:deactivate_test_suite).with(test_suite_name)
        end
      end

      context "and there are only skipped tests" do
        before do
          ci_test_suite.record_test_result(Datadog::CI::Ext::Test::Status::SKIP)
        end

        it "sets the status to skip" do
          expect(tracer_span).to receive(:set_tag).with(
            Datadog::CI::Ext::Test::TAG_STATUS, Datadog::CI::Ext::Test::Status::SKIP
          )

          finish

          expect(recorder).to have_received(:deactivate_test_suite).with(test_suite_name)
        end
      end

      context "and there are some passed tests" do
        before do
          2.times do
            ci_test_suite.record_test_result(Datadog::CI::Ext::Test::Status::SKIP)
          end
          ci_test_suite.record_test_result(Datadog::CI::Ext::Test::Status::PASS)
        end

        it "sets the status to pass" do
          expect(tracer_span).to receive(:set_tag).with(
            Datadog::CI::Ext::Test::TAG_STATUS, Datadog::CI::Ext::Test::Status::PASS
          )

          finish

          expect(recorder).to have_received(:deactivate_test_suite).with(test_suite_name)
        end
      end
    end
  end
end
