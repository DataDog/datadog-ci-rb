# frozen_string_literal: true

RSpec.describe Datadog::CI::TestSuite do
  let(:test_suite_name) { "my.suite" }
  let(:tracer_span) { instance_double(Datadog::Tracing::SpanOperation, finish: true, name: test_suite_name) }
  let(:test_visibility) { spy("test_visibility") }

  before { allow_any_instance_of(described_class).to receive(:test_visibility).and_return(test_visibility) }
  subject(:ci_test_suite) { described_class.new(tracer_span) }

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

        expect(test_visibility).to have_received(:deactivate_test_suite).with(test_suite_name)
      end
    end

    context "when test suite has no status" do
      let(:test_suite_status) { nil }

      context "and there are test failures" do
        before do
          ci_test_suite.record_test_result("t1", Datadog::CI::Ext::Test::Status::PASS)
          ci_test_suite.record_test_result("t2", Datadog::CI::Ext::Test::Status::SKIP)
          ci_test_suite.record_test_result("t3", Datadog::CI::Ext::Test::Status::FAIL)
        end

        it "sets the status to fail" do
          expect(tracer_span).to receive(:set_tag).with(
            Datadog::CI::Ext::Test::TAG_STATUS, Datadog::CI::Ext::Test::Status::FAIL
          )
          expect(tracer_span).to receive(:status=).with(1)

          finish

          expect(test_visibility).to have_received(:deactivate_test_suite).with(test_suite_name)
        end
      end

      context "and there are only skipped tests" do
        before do
          ci_test_suite.record_test_result("t1", Datadog::CI::Ext::Test::Status::SKIP)
          ci_test_suite.record_test_result("t2", Datadog::CI::Ext::Test::Status::SKIP)
          ci_test_suite.record_test_result("t3", Datadog::CI::Ext::Test::Status::SKIP)
        end

        it "sets the status to skip" do
          expect(tracer_span).to receive(:set_tag).with(
            Datadog::CI::Ext::Test::TAG_STATUS, Datadog::CI::Ext::Test::Status::SKIP
          )

          finish

          expect(test_visibility).to have_received(:deactivate_test_suite).with(test_suite_name)
        end
      end

      context "and there are some passed tests" do
        before do
          2.times do |i|
            ci_test_suite.record_test_result("t#{i}", Datadog::CI::Ext::Test::Status::SKIP)
          end
          ci_test_suite.record_test_result("t2", Datadog::CI::Ext::Test::Status::PASS)
        end

        it "sets the status to pass" do
          expect(tracer_span).to receive(:set_tag).with(
            Datadog::CI::Ext::Test::TAG_STATUS, Datadog::CI::Ext::Test::Status::PASS
          )

          finish

          expect(test_visibility).to have_received(:deactivate_test_suite).with(test_suite_name)
        end
      end

      context "some tests were retried and succeeeded on retries" do
        before do
          ci_test_suite.record_test_result("t1", Datadog::CI::Ext::Test::Status::FAIL)
          ci_test_suite.record_test_result("t1", Datadog::CI::Ext::Test::Status::PASS)
          ci_test_suite.record_test_result("t2", Datadog::CI::Ext::Test::Status::SKIP)
        end

        it "sets the status to pass" do
          expect(tracer_span).to receive(:set_tag).with(
            Datadog::CI::Ext::Test::TAG_STATUS, Datadog::CI::Ext::Test::Status::PASS
          )

          finish

          expect(test_visibility).to have_received(:deactivate_test_suite).with(test_suite_name)
        end
      end
    end
  end
end
