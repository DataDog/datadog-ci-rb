# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/utils/test_execution"

RSpec.describe Datadog::CI::Utils::TestExecution do
  subject(:execution) { described_class.new }

  it "allows repeated lifecycle transitions on one fiber" do
    3.times { expect(execution.synchronize { :result }).to eq(:result) }
  end

  it "rejects a sequential handoff to another thread and warns once" do
    execution.synchronize { true }
    allow(Datadog.logger).to receive(:warn)
    expect(Thread.new { execution.synchronize { :unexpected } }.value).to be_nil
    expect(execution.synchronize { :unexpected }).to be_nil
    expect(execution).not_to be_enabled
    expect(Datadog.logger).to have_received(:warn).once
  end

  it "rejects a sibling fiber even on the same thread" do
    execution.synchronize { true }
    expect(Fiber.new { execution.synchronize { :unexpected } }.resume).to be_nil
    expect(execution).not_to be_enabled
  end

  it "does not mistake application background work for a lifecycle handoff" do
    execution.synchronize { true }
    expect(Thread.new { execution.enabled? }.value).to be(true)
    expect(Fiber.new { execution.enabled? }.resume).to be(true)
    expect(execution.synchronize { :result }).to eq(:result)
  end

  it "discards collection once when disabled" do
    callback = spy("discard")
    execution.on_disable { callback.call }
    execution.disable!("unsupported executor")
    execution.disable!("unsupported executor")
    expect(callback).to have_received(:call).once
  end

  it "allows a forked worker to establish its own owner" do
    execution.synchronize { true }
    expect_in_fork do
      expect(Thread.new { execution.synchronize { :child } }.value).to eq(:child)
    end
    expect(execution.synchronize { :parent }).to eq(:parent)
  end
end
