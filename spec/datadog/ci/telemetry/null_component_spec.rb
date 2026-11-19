# frozen_string_literal: true

require "spec_helper"
require "datadog/ci/telemetry/null_component"

RSpec.describe Datadog::CI::Telemetry::NullComponent do
  it "supports the enabled component API without collecting data" do
    telemetry = described_class.new
    expect(telemetry.enabled?).to be(false)
    expect(telemetry.enabled).to be(false)
    expect(telemetry.inc("civisibility", "events", 1, tags: {})).to be_nil
    expect(telemetry.distribution("civisibility", "duration", 1.0, tags: {})).to be_nil
    expect(telemetry.flush).to be_nil
    expect(telemetry.disable!).to be_nil
    expect(telemetry.shutdown!).to be_nil
  end
end
