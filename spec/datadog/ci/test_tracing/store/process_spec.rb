# frozen_string_literal: true

require_relative "../../../../../lib/datadog/ci/test_tracing/store/process"

RSpec.describe Datadog::CI::TestTracing::Store::Process do
  subject(:context) { described_class.new }

  let(:tracer_span) { double(Datadog::Tracing::SpanOperation, name: "test.session", service: "my-service") }
  let(:session) { Datadog::CI::TestSession.new(tracer_span) }
  let(:test_module) { Datadog::CI::TestModule.new(tracer_span) }

  describe "#active_test_session" do
    context "when a test session is active" do
      before do
        subject.fetch_or_activate_test_session { session }
      end

      it "returns the active test session" do
        expect(subject.active_test_session).to be(session)
      end
    end

    context "when no test session is active" do
      it "returns nil" do
        expect(subject.active_test_session).to be_nil
      end
    end
  end

  describe "#deactivate_test_session!" do
    context "when a test session is active" do
      before do
        subject.fetch_or_activate_test_session { session }
      end

      it "deactivates the test session" do
        subject.deactivate_test_session!
        expect(subject.active_test_session).to be_nil
      end
    end

    context "when no test session is active" do
      it "does nothing" do
        subject.deactivate_test_session!
        expect(subject.active_test_session).to be_nil
      end
    end
  end

  describe "active_test_module" do
    context "when a test module is active" do
      before do
        subject.fetch_or_activate_test_module { test_module }
      end

      it "returns the active test module" do
        expect(subject.active_test_module).to be(test_module)
      end
    end

    context "when no test module is active" do
      it "returns nil" do
        expect(subject.active_test_module).to be_nil
      end
    end
  end

  describe "#deactivate_test_module!" do
    context "when a test module is active" do
      before do
        subject.fetch_or_activate_test_module { test_module }
      end

      it "deactivates the test module" do
        subject.deactivate_test_module!
        expect(subject.active_test_module).to be_nil
      end
    end

    context "when no test module is active" do
      it "does nothing" do
        subject.deactivate_test_module!
        expect(subject.active_test_module).to be_nil
      end
    end
  end

  describe "#fetch_or_activate_test_suite" do
    let(:test_suite_name) { "my.suite" }
    let(:tracer_span) { double(Datadog::Tracing::SpanOperation, name: test_suite_name) }
    let(:test_suite) { Datadog::CI::TestSuite.new(tracer_span) }

    context "when a test suite is already active" do
      before do
        subject.fetch_or_activate_test_suite(test_suite_name) { test_suite }
      end

      it "returns the active test suite without calling the block" do
        block_spy = spy("block")
        result = subject.fetch_or_activate_test_suite(test_suite_name) do
          block_spy.call
          Datadog::CI::TestSuite.new(tracer_span)
        end

        expect(result).to be(test_suite)
        expect(block_spy).not_to have_received(:call)
      end
    end

    context "when a test suite with this name is not active" do
      before do
        subject.fetch_or_activate_test_suite("another.suite") do
          Datadog::CI::TestSuite.new(double(Datadog::Tracing::SpanOperation))
        end
      end

      it "activates this test suite and returns it" do
        block_spy = spy("block")
        result = subject.fetch_or_activate_test_suite(test_suite_name) do
          block_spy.call
          test_suite
        end

        expect(result).to be(test_suite)
        expect(block_spy).to have_received(:call)
      end
    end

    context "concurrently trying to start the same test suite" do
      include_context "Concurrency test"

      it "activates this test suite only once" do
        repeat do
          subject.deactivate_test_suite!(test_suite_name)

          block_spy = spy("block")

          run_concurrently do
            subject.fetch_or_activate_test_suite(test_suite_name) do
              block_spy.call
              test_suite
            end
          end

          expect(block_spy).to have_received(:call).once
        end
      end
    end
  end

  describe "#fetch_single_test_suite" do
    let(:test_suite_name) { "my.suite" }
    let(:tracer_span) { double(Datadog::Tracing::SpanOperation, name: test_suite_name) }
    let(:test_suite) { Datadog::CI::TestSuite.new(tracer_span) }

    context "when a single test suite is active" do
      before do
        subject.fetch_or_activate_test_suite(test_suite_name) { test_suite }
      end

      it "returns the single active test suite" do
        result = subject.fetch_single_test_suite

        expect(result).to be(test_suite)
      end
    end

    context "when no test suites are running" do
      it "returns nil" do
        expect(subject.fetch_single_test_suite).to be_nil
      end
    end

    context "when multiple test suites are running" do
      before do
        %w[suite1 suite2].each do |test_suite_name|
          subject.fetch_or_activate_test_suite(test_suite_name) do
            Datadog::CI::TestSuite.new(double(Datadog::Tracing::SpanOperation))
          end
        end
      end

      it "returns nil" do
        expect(subject.fetch_single_test_suite).to be_nil
      end
    end
  end

  describe "#fetch_or_activate_test_module" do
    let(:test_module_name) { "my.module" }
    let(:tracer_span) { double(Datadog::Tracing::SpanOperation, name: test_module_name) }
    let(:test_module) { Datadog::CI::TestModule.new(tracer_span) }

    context "when a test module is already active" do
      before do
        subject.fetch_or_activate_test_module { test_module }
      end

      it "returns the active test module without calling the block" do
        block_spy = spy("block")
        result = subject.fetch_or_activate_test_module do
          block_spy.call
          Datadog::CI::TestModule.new(tracer_span)
        end

        expect(result).to be(test_module)
        expect(block_spy).not_to have_received(:call)
      end
    end

    context "when a test module is not active" do
      it "activates this test module and returns it" do
        block_spy = spy("block")
        result = subject.fetch_or_activate_test_module do
          block_spy.call
          test_module
        end

        expect(result).to be(test_module)
        expect(block_spy).to have_received(:call)
      end
    end
  end

  describe "#fetch_or_activate_test_session" do
    context "when a test session is already active" do
      before do
        subject.fetch_or_activate_test_session { session }
      end

      it "returns the active test session without calling the block" do
        block_spy = spy("block")
        result = subject.fetch_or_activate_test_session do
          block_spy.call
          Datadog::CI::TestSession.new(tracer_span)
        end

        expect(result).to be(session)
        expect(block_spy).not_to have_received(:call)
      end
    end

    context "when a test session is not active" do
      it "activates this test session and returns it" do
        block_spy = spy("block")
        result = subject.fetch_or_activate_test_session do
          block_spy.call
          session
        end

        expect(result).to be(session)
        expect(block_spy).to have_received(:call)
      end
    end
  end

  describe "#stop_all_test_suites" do
    let(:test_suite1) { instance_double(Datadog::CI::TestSuite) }
    let(:test_suite2) { instance_double(Datadog::CI::TestSuite) }

    before do
      allow(test_suite1).to receive(:finish)
      allow(test_suite2).to receive(:finish)

      subject.fetch_or_activate_test_suite("suite1") { test_suite1 }
      subject.fetch_or_activate_test_suite("suite2") { test_suite2 }
    end

    it "calls finish on all test suites and clears the list" do
      subject.stop_all_test_suites

      expect(test_suite1).to have_received(:finish)
      expect(test_suite2).to have_received(:finish)
      expect(subject.active_test_suite("suite1")).to be_nil
      expect(subject.active_test_suite("suite2")).to be_nil
    end
  end

  describe "#deactivate_test_suite!" do
    let(:test_suite) { instance_double(Datadog::CI::TestSuite) }

    before do
      subject.fetch_or_activate_test_suite("suite") { test_suite }
    end

    it "removes the test suite from the active list" do
      subject.deactivate_test_suite!("suite")
      expect(subject.active_test_suite("suite")).to be_nil
    end
  end
end
