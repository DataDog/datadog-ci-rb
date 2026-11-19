# frozen_string_literal: true

RSpec.describe Datadog::CI::Configuration::Base do
  let(:settings_class) do
    Class.new do
      include Datadog::CI::Configuration::Base

      option(:enabled) { |o|
        o.type :bool
        o.env "ENABLED"
        o.default false
      }
      option(:attempts) { |o|
        o.type :int
        o.env "ATTEMPTS"
        o.default 3
      }
      option(:tags) { |o| o.default({}) }
    end
  end

  it "reads typed configuration from the injected environment" do
    settings = settings_class.new(environment: {"ENABLED" => "true", "ATTEMPTS" => "4"})
    expect(settings.enabled).to be(true)
    expect(settings.attempts).to eq(4)
  end

  it "does not share mutable defaults" do
    first = settings_class.new(environment: {})
    second = settings_class.new(environment: {})
    first.tags["key"] = "value"
    expect(second.tags).to be_empty
  end

  it "preserves explicit values when importing legacy configuration" do
    settings = settings_class.new(environment: {})
    settings.attempts = 2
    settings.import_option_if_unset(:attempts, 8)
    expect(settings.attempts).to eq(2)
  end

  it "refreshes imported values before a session starts" do
    settings = settings_class.new(environment: {})
    settings.import_option_if_unset(:attempts, 8)
    settings.import_option_if_unset(:attempts, 4)
    expect(settings.attempts).to eq(4)
  end

  it "resolves the environment again after an explicit reset" do
    environment = {"ATTEMPTS" => "4"}
    settings = settings_class.new(environment: environment)
    expect(settings.attempts).to eq(4)
    environment["ATTEMPTS"] = "6"
    settings.reset!
    expect(settings.attempts).to eq(6)
  end
end
