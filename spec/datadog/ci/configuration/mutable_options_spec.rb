# frozen_string_literal: true

RSpec.describe "Mutable CI configuration" do
  let(:settings_class) do
    Class.new do
      include Datadog::CI::Configuration::Base

      option(:tags) { |option| option.default({}) }
      option(:filters) { |option| option.default([]) }
    end
  end
  let(:settings) { settings_class.new(environment: {}) }

  it "preserves direct hash edits when importing legacy values" do
    settings.tags["custom"] = "ci"
    settings.import_option_if_unset(:tags, {"legacy" => "application"})

    expect(settings.tags).to eq("custom" => "ci")
    expect(settings.explicit?(:tags)).to be(true)
  end

  it "preserves direct array edits when importing legacy values" do
    settings.filters << "native"
    settings.import_option_if_unset(:filters, ["legacy"])

    expect(settings.filters).to eq(["native"])
    expect(settings.explicit?(:filters)).to be(true)
  end

  it "continues to refresh mutable legacy values after native reads" do
    expect(settings.tags).to be_empty
    settings.import_option_if_unset(:tags, {"legacy" => "first"})
    expect(settings.tags).to eq("legacy" => "first")
    settings.import_option_if_unset(:tags, {"legacy" => "second"})

    expect(settings.tags).to eq("legacy" => "second")
    expect(settings.explicit?(:tags)).to be(false)
  end

  it "preserves nested edits without changing the legacy object" do
    legacy = {"nested" => [{"label" => +"legacy"}]}
    settings.import_option_if_unset(:tags, legacy)
    settings.tags["nested"].first["label"].replace("native")
    settings.import_option_if_unset(:tags, {"replacement" => true})

    expect(settings.tags).to eq("nested" => [{"label" => "native"}])
    expect(legacy).to eq("nested" => [{"label" => "legacy"}])
  end

  it "imports subsequent legacy mutations until native values change" do
    legacy = ["first"]
    settings.import_option_if_unset(:filters, legacy)
    legacy << "second"
    expect(settings.filters).to eq(["first"])
    settings.import_option_if_unset(:filters, legacy)
    expect(settings.filters).to eq(["first", "second"])
    settings.filters.clear
    settings.import_option_if_unset(:filters, legacy)
    expect(settings.filters).to be_empty
  end

  it "retains explicit assignments even when they match imported defaults" do
    settings.tags = {}
    settings.import_option_if_unset(:tags, {"legacy" => "value"})

    expect(settings.tags).to be_empty
    expect(settings.explicit?(:tags)).to be(true)
  end

  it "releases mutation precedence after reset" do
    settings.tags["native"] = "value"
    settings.import_option_if_unset(:tags, {"ignored" => "value"})
    settings.reset!
    settings.import_option_if_unset(:tags, {"legacy" => "value"})

    expect(settings.tags).to eq("legacy" => "value")
    expect(settings.explicit?(:tags)).to be(false)
  end

  it "copies recursive containers without recursion errors" do
    legacy = {"values" => []}
    legacy["values"] << legacy
    settings.import_option_if_unset(:tags, legacy)
    expect(settings.tags["values"].first).to equal(settings.tags)
    expect(settings.tags).not_to equal(legacy)
    expect(settings.explicit?(:tags)).to be(false)
  end

  it "keeps tags edited inside the native configuration block" do
    Datadog::CI.configure do |configuration|
      configuration.ci.enabled = false
      configuration.tags["custom"] = "native"
    end
    Datadog.configuration.tags = {"legacy" => "application"}

    expect(Datadog::CI.configuration.tags).to eq("custom" => "native")
  end

  it "keeps tags edited through direct native configuration access" do
    Datadog.configuration.tags = {"legacy" => "first"}
    Datadog::CI.configuration.tags["custom"] = "native"
    Datadog.configuration.tags = {"legacy" => "second"}

    expect(Datadog::CI.configuration.tags).to eq("legacy" => "first", "custom" => "native")
    expect(Datadog.configuration.tags).to eq("legacy" => "second")
  end

  it "imports direct legacy tag edits before the test session starts" do
    Datadog.configuration.tags = {"legacy" => "first"}
    expect(Datadog::CI.configuration.tags).to eq("legacy" => "first")
    Datadog.configuration.tags["legacy"] = "second"

    expect(Datadog::CI.configuration.tags).to eq("legacy" => "second")
  end
end
