# frozen_string_literal: true

require "minitest"
require "minitest/spec"

module Kernel
  alias_method :minitest_describe, :describe
end

RSpec.describe "Minitest discovery source files" do
  include_context "CI mode activated" do
    let(:integration_name) { :minitest }
    let(:test_discovery_enabled) { true }
  end

  let(:fixture_path) { "spec/datadog/ci/contrib/minitest/helpers/discovery_test.rb" }
  let(:shared_path) { "spec/datadog/ci/contrib/minitest/helpers/shared_discovery_tests.rb" }
  let(:helpers) { Datadog::CI::Contrib::Minitest::Helpers }

  before do
    Minitest::Runnable.reset
    load File.expand_path("helpers/discovery_test.rb", __dir__)
    Minitest::Runnable.runnables.delete(SharedDiscoveryBase)
  end

  after do
    Minitest::Runnable.reset
    Object.send(:remove_const, :MinitestDiscoveryFixtures)
    FileUtils.rm_rf(Datadog::CI::Ext::TestDiscovery::DEFAULT_OUTPUT_PATH)
  end

  it "discovers executable files for shared, nested, generated, anonymous and ordinary tests without changing identities" do
    Minitest.seed = 1
    identities = Minitest::Runnable.runnables.flat_map do |klass|
      klass.runnable_methods.map { |method| helpers.test_suite_name(klass, method) }
    end

    expect(Minitest.run([])).to be true
    tests = File.readlines(Datadog::CI::Ext::TestDiscovery::DEFAULT_OUTPUT_PATH).map { |line| JSON.parse(line) }

    expect(tests.size).to eq(10)
    expect(tests.map { |test| test["suite"] }).to match_array(identities)
    expect(tests.map { |test| test["suiteSourceFile"] }.uniq).to eq([fixture_path])
    expect(tests).to include(hash_including("suite" => "CustomerContract at #{shared_path}", "name" => "test_contract"))
    expect(tests).to include(hash_including("suite" => "MinitestDiscoveryFixtures::ClassContract at #{fixture_path}"))
    expect(tests).to include(hash_including("suite" => "SimpleModel at #{fixture_path}"))
    expect(test_spans).to be_empty
  end

  it "falls back to existing source attribution if definition metadata is unavailable" do
    klass = Minitest::Runnable.runnables.find { |runnable| runnable.name == "CustomerContract" }
    klass.dd_spec_source_file = nil

    expect(helpers.discovery_source_file(klass, "test_contract")).to eq(klass.instance_method(:test_contract).source_location.first)
  end

  it "logs capture failures and leaves the customer's runnable intact" do
    allow(Datadog::CI::Contrib::Minitest::SpecSourceLocation).to receive(:resolve).and_raise("capture failed")
    expect(Datadog.logger).to receive(:warn).with(include("Could not capture Minitest spec definition", "capture failed"))

    klass = Class.new(Minitest::Spec) { include SharedDiscoveryMethods }
    expect(Minitest::Runnable.runnables).to include(klass)
    expect(klass.dd_spec_source_file).to be_nil
    expect(klass.new("test_shared_nested").run.passed?).to be true
  end

  context "during execution" do
    let(:test_discovery_enabled) { false }

    it "preserves shared-method source attribution" do
      expect(Minitest.run([])).to be true
      contract = test_spans.find { |span| span.name == "test_contract" }
      suite = test_suite_spans.find { |span| span.name == "CustomerContract at #{shared_path}" }

      expect(contract).to have_test_tag(:suite, "CustomerContract at #{shared_path}")
      expect(contract).to have_test_tag(:source_file, shared_path)
      expect(suite).to have_test_tag(:source_file, shared_path)
    end
  end
end
