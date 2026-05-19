# frozen_string_literal: true

require "tmpdir"

require_relative "../../../../lib/datadog/ci/utils/json"

RSpec.describe Datadog::CI::Utils::Json do
  it "loads JSON from disk" do
    Dir.mktmpdir do |tmpdir|
      path = File.join(tmpdir, "payload.json")
      File.write(path, JSON.generate("ok" => true))

      expect(described_class.read_file(path)).to eq("ok" => true)
    end
  end

  it "returns nil when JSON is invalid" do
    Dir.mktmpdir do |tmpdir|
      path = File.join(tmpdir, "payload.json")
      File.write(path, "{")

      expect(described_class.read_file(path)).to be_nil
    end
  end

  it "reads the current payload from disk" do
    Dir.mktmpdir do |tmpdir|
      path = File.join(tmpdir, "payload.json")
      File.write(path, JSON.generate("ok" => true))

      expect(described_class.read_file(path)).to eq("ok" => true)

      File.write(path, JSON.generate("ok" => false))

      expect(described_class.read_file(path)).to eq("ok" => false)
    end
  end
end
