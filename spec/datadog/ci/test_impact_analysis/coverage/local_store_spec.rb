# frozen_string_literal: true

require "tmpdir"
require_relative "../../../../../lib/datadog/ci/test_impact_analysis/coverage/local_store"
require_relative "../../../../../lib/datadog/ci/test_impact_analysis/coverage/files"

RSpec.describe Datadog::CI::TestImpactAnalysis::Coverage::LocalStore do
  around do |example|
    Dir.mktmpdir("local-tia-store") do |directory|
      @directory = directory
      example.run
    end
  end

  let(:path) { File.join(@directory, "coverage.json.gz") }
  let(:git) { instance_double(Datadog::CI::TestImpactAnalysis::Coverage::LocalGit, head: "a" * 40, changed_files: []) }
  let(:test) { instance_double(Datadog::CI::Test, test_suite_name: "Cart", name: "works", parameters: '{"metadata":{"scoped_id":"1:1"}}', passed?: true) }
  let(:files) { instance_double(Datadog::CI::TestImpactAnalysis::Coverage::Files) }

  def build(repository: "git@github.com:team/project.git", framework: "rspec", variant: nil)
    described_class.new(path: path, root: @directory, repository: repository, framework: framework, variant: variant, git: git)
  end

  def collect
    writer = build
    writer.record(test, files)
    writer.finish
  end

  before { allow(files).to receive(:each).and_yield("lib/cart.rb").and_yield("spec/cart_spec.rb") }

  it "writes the simplified gzip JSON format and reloads it across URL schemes" do
    collect
    document = JSON.parse(Zlib.gunzip(File.binread(path)))
    expect(document.keys).to match_array(%w[version scope base_commit tests])
    expect(document["scope"]).to eq("repository" => "github.com/team/project", "framework" => "rspec")
    expect(document.fetch("tests").first).to eq(
      "suite" => "Cart", "name" => "works", "parameters" => {"metadata" => {"scoped_id" => "1:1"}},
      "files" => ["lib/cart.rb", "spec/cart_spec.rb"]
    )
    reader = build(repository: "https://github.com/team/project.git")
    expect(reader.collecting?).to be false
    expect(reader.skippable?(test)).to be true
  end

  it "selects dependents from Git changes and ignores unrelated changes" do
    collect
    allow(git).to receive(:changed_files).with("a" * 40).and_return(["lib/cart.rb"])
    expect(build.skippable?(test)).to be false
    allow(git).to receive(:changed_files).and_return(["README.md"])
    expect(build.skippable?(test)).to be true
  end

  it "unions repeated observations without overwriting the baseline on selection runs" do
    writer = build
    writer.record(test, files)
    allow(files).to receive(:each).and_yield("lib/extra.rb")
    writer.record(test, files)
    writer.finish
    bytes = File.binread(path)
    expect(JSON.parse(Zlib.gunzip(bytes))["tests"].first["files"]).to include("lib/extra.rb", "lib/cart.rb")
    reader = build
    reader.record(test, files)
    reader.finish
    expect(File.binread(path)).to eq(bytes)
  end

  it "does not persist failed tests or an unfinished collection" do
    writer = build
    allow(test).to receive(:passed?).and_return(false)
    writer.record(test, files)
    expect(File.exist?(path)).to be false
    writer.finish
    expect(File.exist?(path)).to be false
  end

  it "does not overwrite a concurrently published snapshot" do
    writer = build
    writer.record(test, files)
    File.binwrite(path, "another snapshot")
    expect(Datadog.logger).to receive(:warn).with(/Local TIA coverage/)
    writer.finish
    expect(File.binread(path)).to eq("another snapshot")
  end

  it "rejects dirty baselines and discards collection when the checkout changes" do
    allow(git).to receive(:changed_files).and_return(["lib/cart.rb"])
    expect { build }.to raise_error(RuntimeError, /clean Git checkout/)
    allow(git).to receive(:changed_files).and_return([])
    writer = build
    writer.record(test, files)
    allow(git).to receive(:head).and_return("b" * 40)
    expect(Datadog.logger).to receive(:warn).with(/Checkout changed/)
    writer.finish
    expect(File.exist?(path)).to be false
  end

  it "rejects corrupt maps and mismatched scopes without replacing them" do
    collect
    bytes = File.binread(path)
    expect { build(framework: "minitest") }.to raise_error(ArgumentError)
    expect { build(variant: "other") }.to raise_error(ArgumentError)
    expect { build(repository: "https://github.com/team/other.git") }.to raise_error(ArgumentError)
    expect(File.binread(path)).to eq(bytes)
    File.binwrite(path, "broken")
    expect { build }.to raise_error(Zlib::Error)
    expect(File.binread(path)).to eq("broken")
  end

  it "runs tests with unknown identities or malformed parameters" do
    collect
    reader = build
    allow(test).to receive(:parameters).and_return(nil)
    expect(reader.skippable?(test)).to be false
    allow(test).to receive(:parameters).and_return("invalid JSON")
    expect(Datadog.logger).to receive(:warn).with(/Local TIA coverage/)
    expect(reader.skippable?(test)).to be false
  end
end
