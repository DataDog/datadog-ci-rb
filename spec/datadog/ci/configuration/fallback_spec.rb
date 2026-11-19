# frozen_string_literal: true

require "datadog/ci/configuration/fallback"

RSpec.describe Datadog::CI::Configuration::Fallback do
  let(:settings) { double(:settings, ci: double(:ci_settings)) }
  let(:host) { Module.new.extend(described_class) }

  it "delegates existing configuration reads to the independent runtime" do
    allow(Datadog::CI).to receive(:configuration).and_return(settings)

    expect(host.configuration).to equal(settings)
    expect(host.configuration.ci).to equal(settings.ci)
  end

  it "passes existing configuration blocks to the independent runtime" do
    allow(Datadog::CI).to receive(:configure).and_yield(settings).and_return(settings)
    received = nil

    result = host.configure { |configuration| received = configuration }

    expect(received).to equal(settings)
    expect(result).to equal(settings)
  end

  it "lets a subsequently loaded tracer take ownership of its configuration API" do
    tracer_settings = Object.new
    tracer_api = Module.new do
      define_method(:configuration) { tracer_settings }
    end
    host.extend(tracer_api)

    expect(host.configuration).to equal(tracer_settings)
  end
end
