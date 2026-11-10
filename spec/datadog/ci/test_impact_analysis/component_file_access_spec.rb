# frozen_string_literal: true

require "tmpdir"
require_relative "../../../../lib/datadog/ci/test_impact_analysis/component"

RSpec.describe Datadog::CI::TestImpactAnalysis::Component, "file dependencies" do
  let(:root) { Datadog::CI::Git::LocalRepository.root }
  let(:directory) { Dir.mktmpdir("file-dependencies-", root) }
  let(:fixture) { File.join(directory, "fixture.json") }
  let(:shared_fixture) { File.join(directory, "shared.yml") }
  let(:writer) { spy("coverage writer") }
  let(:mode) { "test" }
  let(:component) { described_class.new(dd_env: "test", enabled: true, coverage_writer: writer, test_skipping_mode: mode) }
  let(:session) { Datadog::CI::TestSession.new(Datadog::Tracing::SpanOperation.new("session")) }
  let(:suite) do
    span = Datadog::Tracing::SpanOperation.new("suite")
    span.set_tag(Datadog::CI::Ext::Test::TAG_TEST_SESSION_ID, session.id.to_s)
    Datadog::CI::TestSuite.new(span)
  end
  let(:context) { instance_double(Datadog::CI::TestTracing::Context, incr_tests_skipped_by_tia_count: nil) }

  def new_test
    span = Datadog::Tracing::SpanOperation.new("test")
    span.set_tag(Datadog::CI::Ext::Test::TAG_TEST_SESSION_ID, session.id.to_s)
    span.set_tag(Datadog::CI::Ext::Test::TAG_TEST_SUITE_ID, suite.id.to_s)
    Datadog::CI::Test.new(span).tap do |test|
      allow(test).to receive(:test_suite).and_return(suite)
    end
  end

  before do
    File.write(fixture, '{"value":42}')
    File.write(shared_fixture, "value: 42\n")
    settings = double("settings", itr_enabled?: true, code_coverage_enabled?: true, tests_skipping_enabled?: false)
    component.configure(settings, session)
  end

  after do
    component.shutdown!
    FileUtils.remove_entry(directory)
  end

  it "attributes a fixture to the test that opened it, including the wire payload" do
    first = new_test
    component.on_test_started(first)
    expect(JSON.parse(File.read(fixture))).to eq("value" => 42)
    first_event = component.on_test_finished(first, context)
    second = new_test
    component.on_test_started(second)
    second_event = component.on_test_finished(second, context)

    expect(first_event.inspect_coverage).to include(fixture => true)
    expect(second_event.inspect_coverage).not_to have_key(fixture)
    payload = MessagePack.unpack(MessagePack.pack(first_event))
    expect(payload.fetch("files")).to include({"filename" => fixture.delete_prefix(root + "/")})
    expect(writer).to have_received(:write).with(first_event)
  end

  it "inherits context fixtures for every test in that context" do
    component.on_test_context_started("group")
    File.read(shared_fixture)
    2.times do
      test = new_test
      test.context_ids = ["group"]
      component.on_test_started(test)
      event = component.on_test_finished(test, context)
      expect(event.inspect_coverage).to include(shared_fixture => true)
    end
    component.clear_context_coverage("group")
    test = new_test
    test.context_ids = ["group"]
    component.on_test_started(test)
    expect(component.on_test_finished(test, context).inspect_coverage).not_to have_key(shared_fixture)
  end

  it "discards dependencies for skipped tests" do
    test = new_test
    component.on_test_started(test)
    File.read(fixture)
    test.skipped!
    expect(component.on_test_finished(test, context)).to be_nil
    expect(writer).not_to have_received(:write)
  end

  it "stops unfinished file collection at shutdown" do
    test = new_test
    component.on_test_started(test)
    component.shutdown!
    File.read(fixture)
    expect(component.stop_coverage).not_to have_key(fixture)
  end

  context "with suite attribution" do
    let(:mode) { "suite" }

    it "keeps test fixtures in the enclosing suite event" do
      component.on_test_suite_started(suite)
      test = new_test
      component.on_test_started(test)
      File.read(fixture)
      component.on_test_finished(test, context)
      event = component.on_test_suite_finished(suite, context)
      expect(event.test_id).to be_nil
      expect(event.test_suite_id).to eq(suite.id.to_s)
      expect(event.inspect_coverage).to include(fixture => true)
    end
  end
end
