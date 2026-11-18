# frozen_string_literal: true

require_relative "../../../../../lib/datadog/ci/test_impact_analysis/coverage/local_map"

RSpec.describe Datadog::CI::TestImpactAnalysis::Coverage::LocalMap do
  let(:scope) { {"repository" => "github.com/team/project", "framework" => "rspec"} }
  let(:records) do
    [
      {"suite" => "Cart", "name" => "works", "parameters" => {"metadata" => {"scoped_id" => "1:1"}}, "files" => ["lib/cart.rb", "spec/cart_spec.rb"]},
      {"suite" => "Cart", "name" => "works", "parameters" => {"metadata" => {"scoped_id" => "1:2"}}, "files" => ["lib/billing.rb"]},
      {"suite" => "Empty", "name" => "works", "parameters" => nil, "files" => []}
    ]
  end
  let(:document) { {"version" => 1, "scope" => scope, "base_commit" => "a" * 40, "tests" => records} }
  subject(:map) { described_class.new(document, scope: scope) }

  def identity(index)
    record = records.fetch(index)
    [record.fetch("suite"), record.fetch("name"), record.fetch("parameters")]
  end

  it "selects the union of recorded dependents" do
    map.select(["lib/cart.rb", "README.md", "lib/cart.rb"])
    expect((0..2).map { |index| map.skippable?(identity(index)) }).to eq([false, true, true])
    map.select(["lib/cart.rb", "lib/billing.rb"])
    expect((0..2).map { |index| map.skippable?(identity(index)) }).to eq([false, false, true])
  end

  it "skips recorded tests when changed files have no dependents" do
    map.select(["README.md"])
    expect((0..2).map { |index| map.skippable?(identity(index)) }).to eq([true, true, true])
  end

  it "runs unknown tests and runs all tests until selection succeeds" do
    expect(map.skippable?(identity(0))).to be false
    map.select([])
    expect(map.skippable?(["new", "test", nil])).to be false
  end

  it "preserves structured parameters and ignores object key order" do
    first = described_class.identity("suite", "test", '{"a":1,"b":[true,"1"]}')
    second = described_class.identity("suite", "test", '{"b":[true,"1"],"a":1}')
    expect(first).to eql(second)
    expect(first).not_to eql(described_class.identity("suite", "test", '{"a":"1","b":[true,"1"]}'))
    expect(first).not_to eql(described_class.identity("suite", "test", '{"a":1,"b":["1",true]}'))
  end

  it "rejects duplicate identities" do
    records << records.first.dup
    expect { map }.to raise_error(ArgumentError, "duplicate test identity")
  end

  it "rejects mismatched scopes and versions" do
    expect { described_class.new(document, scope: scope.merge("variant" => "other")) }.to raise_error(ArgumentError)
    document["version"] = 2
    expect { map }.to raise_error(ArgumentError)
  end

  it "rejects obsolete policy fields" do
    %w[always_run global_files files].each do |field|
      expect { described_class.new(document.merge(field => []), scope: scope) }.to raise_error(ArgumentError)
    end
  end

  it "rejects malformed records and paths" do
    [nil, "bad", {"name" => "missing fields"}].each do |record|
      expect { described_class.new(document.merge("tests" => [record]), scope: scope) }.to raise_error(ArgumentError)
    end
    ["/absolute.rb", "../outside.rb", "lib/../outside.rb", "./lib/a.rb", "bad\0.rb", ""].each do |path|
      records.first["files"] = [path]
      expect { described_class.new(document, scope: scope) }.to raise_error(ArgumentError)
    end
  end

  it "rejects non-commit baselines" do
    document["base_commit"] = "--help"
    expect { map }.to raise_error(ArgumentError)
  end
end
