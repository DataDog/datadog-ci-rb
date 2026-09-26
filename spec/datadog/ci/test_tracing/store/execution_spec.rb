# frozen_string_literal: true

require_relative "../../../../../lib/datadog/ci/test_tracing/store/execution"

RSpec.describe Datadog::CI::TestTracing::Store::Execution do
  subject(:store) { described_class.new }
  let(:test) { Datadog::CI::Test.new(Datadog::Tracing::SpanOperation.new("test")) }

  it "exposes a test only to its owning fiber" do
    store.activate_test(test)
    expect(store.active_test).to be(test)
    expect(Thread.new { store.active_test }.value).to be_nil
    expect(Fiber.new { store.active_test }.resume).to be_nil
    Thread.new { store.deactivate_test }.value
    expect(store.active_test).to be(test)
    store.deactivate_test
    expect(store.active_test).to be_nil
  end

  it "cleans up on exceptional block exit" do
    expect do
      store.activate_test(test) { raise "customer failure" }
    end.to raise_error("customer failure")
    expect(store.active_test).to be_nil
  end

  it "does not share active tests between component instances" do
    store.activate_test(test)
    replacement = described_class.new
    expect(replacement.active_test).to be_nil
    replacement.deactivate_test
    expect(store.active_test).to be(test)
  end

  it "does not inherit an active test into a fork" do
    store.activate_test(test)
    expect_in_fork do
      expect(store.active_test).to be_nil
      store.activate_test(test)
      expect(store.active_test).to be(test)
    end
    expect(store.active_test).to be(test)
  end
end
