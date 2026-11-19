# frozen_string_literal: true

require "spec_helper"
require "datadog/ci/utils/only_once"

RSpec.describe Datadog::CI::Utils::OnlyOnce do
  it "runs once and exposes completion until reset" do
    once = described_class.new
    calls = []
    expect(once.ran?).to be(false)
    2.times { once.run { calls << :called } }
    expect(calls).to eq([:called])
    expect(once.ran?).to be(true)
    once.reset!
    expect(once.ran?).to be(false)
    once.run { calls << :again }
    expect(calls).to eq([:called, :again])
  end

  it "allows another attempt after the block raises" do
    once = described_class.new
    expect { once.run { raise IOError, "failed" } }.to raise_error(IOError)
    expect(once.ran?).to be(false)
    once.run { nil }
    expect(once.ran?).to be(true)
  end
end
