# frozen_string_literal: true

RSpec.describe Datadog::CI do
  it "has a version number" do
    expect(Datadog::CI::VERSION).to eq("0.1.0")
  end
end
