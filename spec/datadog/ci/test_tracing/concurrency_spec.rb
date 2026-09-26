# frozen_string_literal: true

RSpec.describe Datadog::CI::TestTracing::Component, "execution ownership" do
  include_context "CI mode activated" do
    let(:itr_enabled) { true }
    let(:code_coverage_enabled) { true }
  end

  before do
    test_tracing.start_test_session
    test_tracing.start_test_module("sequential")
    test_tracing.start_test_suite("suite")
  end

  it "keeps the owning test active while application threads and fibers run" do
    test_tracing.trace_test("owner", "suite") do |test|
      expect(Thread.new { test_tracing.active_test }.value).to be_nil
      expect(Fiber.new { test_tracing.active_test }.resume).to be_nil
      expect(test_tracing.active_test).to be(test)
      test.passed!
    end
    expect(test_tracing.active_test).to be_nil
    expect(test_tracing).to be_execution_supported
  end

  it "restores the enclosing trace after a test block exits" do
    Datadog::Tracing.trace("enclosing") do |outer|
      test_tracing.trace_test("inner test", "suite") { |test| test.passed! }
      expect(Datadog::Tracing.active_span).to be(outer)
    end
  end

  it "does not finalize a later attempt when a finished test is finished again" do
    first = test_tracing.trace_test("first", "suite")
    first.finish
    second = test_tracing.trace_test("second", "suite")
    first.finish
    expect(test_tracing.active_test).to be(second)
    expect(test_tracing).to be_execution_supported
    second.finish
  end

  it "finalizes coverage exactly once when the customer's block raises" do
    impact = Datadog.send(:components).test_impact_analysis
    allow(impact).to receive(:on_test_finished).and_call_original
    expect do
      test_tracing.trace_test("raising", "suite") { raise "customer failure" }
    end.to raise_error("customer failure")
    expect(impact).to have_received(:on_test_finished).once
    expect(test_tracing.active_test).to be_nil
    expect(test_tracing).to be_execution_supported
  end

  it "finalizes coverage while preserving a cancellation exception" do
    impact = Datadog.send(:components).test_impact_analysis
    allow(impact).to receive(:on_test_finished).and_call_original
    cancellation = Interrupt.new("cancelled")
    expect do
      test_tracing.trace_test("cancelled", "suite") { raise cancellation }
    end.to raise_error { |error| expect(error).to be(cancellation) }
    expect(impact).to have_received(:on_test_finished).once
    expect(test_tracing.active_test).to be_nil
  end

  it "runs the customer block without instrumentation if initialization fails" do
    impact = Datadog.send(:components).test_impact_analysis
    allow(impact).to receive(:on_test_started).and_raise("instrumentation failure")
    expect(impact).not_to receive(:write)
    expect(test_tracing.trace_test("owner", "suite") { |test| [test, :ran] }).to eq([nil, :ran])
    expect(test_tracing).not_to be_execution_supported
  end

  it "does not finalize twice when the block explicitly finishes its test" do
    impact = Datadog.send(:components).test_impact_analysis
    allow(impact).to receive(:on_test_finished).and_call_original
    test_tracing.trace_test("explicit finish", "suite") { |test| test.finish }
    expect(impact).to have_received(:on_test_finished).once
    expect(test_tracing).to be_execution_supported
  end

  it "preserves the customer's exception when coverage finalization fails" do
    impact = Datadog.send(:components).test_impact_analysis
    allow(impact).to receive(:on_test_finished).and_raise("instrumentation failure")
    expect do
      test_tracing.trace_test("raising", "suite") { raise "customer failure" }
    end.to raise_error("customer failure")
    expect(test_tracing).not_to be_execution_supported
    expect(impact).not_to be_enabled
  end

  it "runs foreign-thread blocks without instrumentation and discards the active coverage" do
    impact = Datadog.send(:components).test_impact_analysis
    allow(impact).to receive(:write)
    test_tracing.trace_test("owner", "suite") do
      result = Thread.new do
        test_tracing.trace_test("foreign", "suite") do |test|
          expect(test).to be_nil
          :customer_result
        end
      end.value
      expect(result).to eq(:customer_result)
    end
    expect(test_tracing).not_to be_execution_supported
    expect(impact).not_to be_enabled
    expect(impact).not_to have_received(:write)
  end

  it "rejects a sequential handoff to another fiber" do
    test_tracing.trace_test("first", "suite") { |test| test.passed! }
    result = Fiber.new do
      test_tracing.trace_test("second", "suite") { |test| [test, :ran] }
    end.resume
    expect(result).to eq([nil, :ran])
    expect(test_tracing).not_to be_execution_supported
  end

  it "rejects nested attempts without raising or skipping the nested body" do
    test_tracing.trace_test("outer", "suite") do
      expect(test_tracing.trace_test("inner", "suite") { |test| [test, :ran] }).to eq([nil, :ran])
    end
    expect(test_tracing).not_to be_execution_supported
  end

  it "does not publish coverage when a test is finished from another fiber" do
    impact = Datadog.send(:components).test_impact_analysis
    allow(impact).to receive(:write)
    test = test_tracing.trace_test("owner", "suite")
    expect { Thread.new { test.finish }.value }.not_to raise_error
    expect(test_tracing).not_to be_execution_supported
    expect(impact).not_to have_received(:write)
  end
end
