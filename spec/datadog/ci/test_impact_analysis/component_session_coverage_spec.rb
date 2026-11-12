# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require_relative "../../../../lib/datadog/ci/test_impact_analysis/component"

RSpec.describe Datadog::CI::TestImpactAnalysis::Component, "session dependencies" do
  let(:root) { File.realpath(Dir.mktmpdir("session-dependencies")) }
  let(:events) { [] }
  let(:writer) { instance_double(Datadog::CI::AsyncWriter, stop: nil) }
  let(:component) { described_class.new(dd_env: "test", enabled: true, coverage_writer: writer, test_skipping_mode: mode) }
  let(:mode) { Datadog::CI::Ext::Test::TIATestSkippingMode::TEST }
  let(:session) { Datadog::CI::TestSession.new(Datadog::Tracing::SpanOperation.new("session")) }
  let(:suite) { Datadog::CI::TestSuite.new(Datadog::Tracing::SpanOperation.new("suite")) }
  let(:context) { instance_double(Datadog::CI::TestTracing::Context) }
  let(:fixture) { Module.new }
  let(:settings) do
    instance_double(Datadog::CI::Remote::LibrarySettings,
      itr_enabled?: true, code_coverage_enabled?: coverage_enabled, tests_skipping_enabled?: false)
  end
  let(:coverage_enabled) { true }
  let(:test_collector) do
    Datadog::CI::TestImpactAnalysis::Coverage::DDCov.new(
      root: root, ignored_path: nil, threading_mode: :multi, use_allocation_tracing: false
    )
  end

  def define_fixture(name)
    path = File.join(root, "#{name}.rb")
    source = "def self.#{name}; true; end"
    File.write(path, source)
    fixture.module_eval(source, path)
    path
  end

  def run_test(name)
    test = Datadog::CI::Test.new(Datadog::Tracing::SpanOperation.new(name))
    test.set_internal_tag(Datadog::CI::Ext::Test::TAG_TEST_SESSION_ID, session.id.to_s)
    test.set_internal_tag(Datadog::CI::Ext::Test::TAG_TEST_SUITE_ID, suite.id.to_s)
    allow(test).to receive(:test_suite).and_return(suite)
    component.on_test_started(test)
    fixture.public_send(name)
    component.on_test_finished(test, context)
    test
  end

  before do
    allow(Datadog::CI::Git::LocalRepository).to receive(:root).and_return(root)
    allow(writer).to receive(:write) { |event| events << event }
    suite.set_internal_tag(Datadog::CI::Ext::Test::TAG_TEST_SESSION_ID, session.id.to_s)
    component.configure(settings, session)
    # Each example uses a distinct temporary repository; avoid the production
    # thread-local collector retaining a different example's root.
    allow(component).to receive(:coverage_collector).and_return(test_collector) if coverage_enabled
  end

  after do
    component.shutdown!
    test_collector.stop if coverage_enabled
    FileUtils.remove_entry(root)
  end

  it "reports shared setup once and keeps distinct test dependencies local" do
    setup = define_fixture("setup")
    first_file = define_fixture("first")
    second_file = define_fixture("second")
    component.on_test_session_started(session)
    fixture.setup
    component.on_test_suite_started(suite)
    first = run_test("first")
    second = run_test("second")
    component.on_test_session_finished

    expect(events.size).to eq(3)
    shared, first_event, second_event = events
    expect(shared.test_id).to be_nil
    expect(shared.test_suite_id).to be_nil
    expect(shared.test_session_id).to eq(session.id.to_s)
    expect(shared.inspect_coverage).to eq(setup => true)
    expect(first_event.test_id).to eq(first.id.to_s)
    expect(first_event.inspect_coverage).to eq(first_file => true)
    expect(second_event.test_id).to eq(second.id.to_s)
    expect(second_event.inspect_coverage).to eq(second_file => true)
  end

  it "freezes shared coverage once before concurrently starting suites execute" do
    setup = define_fixture("setup")
    define_fixture("first")
    define_fixture("second")
    component.on_test_session_started(session)
    fixture.setup
    ready = Queue.new
    start = Queue.new
    threads = %w[first second].map do |name|
      Thread.new do
        ready << true
        start.pop
        component.on_test_suite_started(suite)
        fixture.public_send(name)
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    threads.each(&:join)
    expect(events.size).to eq(1)
    expect(events.first.inspect_coverage).to eq(setup => true)
  end

  it "freezes session dependencies before context hooks" do
    setup = define_fixture("setup")
    define_fixture("context_setup")
    component.on_test_session_started(session)
    fixture.setup
    component.on_test_context_started("group")
    fixture.context_setup
    component.stop_coverage
    expect(events.one?).to be(true)
    expect(events.first.inspect_coverage).to eq(setup => true)
  end

  it "does not produce coverage for an empty session" do
    define_fixture("setup")
    component.on_test_session_started(session)
    fixture.setup
    component.on_test_session_finished
    component.on_test_suite_started(suite)
    expect(events).to be_empty
  end

  it "does not reset setup when joining the same session again" do
    setup = define_fixture("setup")
    component.on_test_session_started(session)
    fixture.setup
    component.on_test_session_started(session)
    component.on_test_suite_started(suite)
    component.on_test_suite_started(suite)
    expect(events.size).to eq(1)
    expect(events.first.inspect_coverage).to eq(setup => true)
  end

  it "clears setup when another session starts" do
    define_fixture("setup")
    later = define_fixture("later")
    component.on_test_session_started(session)
    fixture.setup
    component.on_test_session_finished
    next_session = Datadog::CI::TestSession.new(Datadog::Tracing::SpanOperation.new("next"))
    component.on_test_session_started(next_session)
    fixture.later
    component.on_test_suite_started(suite)
    expect(events.size).to eq(1)
    expect(events.first.test_session_id).to eq(next_session.id.to_s)
    expect(events.first.inspect_coverage).to eq(later => true)
  end

  it "discards pending setup if coverage is disabled when the session is reconfigured" do
    define_fixture("setup")
    component.on_test_session_started(session)
    fixture.setup
    allow(settings).to receive(:code_coverage_enabled?).and_return(false)
    component.configure(settings, session)
    component.on_test_session_started(session)
    component.on_test_suite_started(suite)
    expect(events).to be_empty
  end

  it "disables collection on shutdown even if the run never reaches a test" do
    define_fixture("setup")
    component.on_test_session_started(session)
    fixture.setup
    component.shutdown!
    component.on_test_suite_started(suite)
    expect(events).to be_empty
  end

  it "contains reporting failures without preventing subsequent test coverage" do
    define_fixture("setup")
    first_file = define_fixture("first")
    component.on_test_session_started(session)
    fixture.setup
    allow(writer).to receive(:write).and_raise("writer failed")
    expect(Datadog.logger).to receive(:warn).with(/Failed to report session coverage/)
    expect { component.on_test_suite_started(suite) }.not_to raise_error
    allow(writer).to receive(:write) { |event| events << event }
    run_test("first")
    expect(events.size).to eq(1)
    expect(events.first.inspect_coverage).to eq(first_file => true)
  end

  context "when coverage is disabled remotely" do
    let(:coverage_enabled) { false }

    it "does not collect or emit session dependencies" do
      define_fixture("setup")
      component.on_test_session_started(session)
      fixture.setup
      component.on_test_suite_started(suite)
      expect(events).to be_empty
    end
  end

  context "with suite-level skipping" do
    let(:mode) { Datadog::CI::Ext::Test::TIATestSkippingMode::SUITE }

    it "keeps shared setup separate from suite dependencies" do
      setup = define_fixture("setup")
      first_file = define_fixture("first")
      component.on_test_session_started(session)
      fixture.setup
      component.on_test_suite_started(suite)
      fixture.first
      component.on_test_suite_finished(suite, context)
      expect(events.size).to eq(2)
      expect(events.first.test_suite_id).to be_nil
      expect(events.first.inspect_coverage).to eq(setup => true)
      expect(events.last.test_suite_id).to eq(suite.id.to_s)
      expect(events.last.inspect_coverage).to eq(first_file => true)
    end
  end
end
