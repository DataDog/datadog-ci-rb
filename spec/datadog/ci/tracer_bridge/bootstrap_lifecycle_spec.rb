# frozen_string_literal: true

RSpec.describe "CI initialization from application tracing" do
  include_context "CI mode activated"

  let(:application_writer) { instance_double(Datadog::Tracing::Writer, write: nil, stop: nil) }

  before do
    Datadog.configure do |settings|
      settings.telemetry.enabled = false
      settings.remote.enabled = false
      settings.tracing.writer = application_writer
    end
  end

  it "does not initialize CI recursively when construction observes an application trace" do
    builds = 0
    allow(Datadog::CI::Configuration::Components).to receive(:new).and_wrap_original do |method, *args|
      builds += 1
      Datadog::Tracing.trace("during construction") {}
      method.call(*args)
    end

    Datadog::Tracing.trace("boot") {}
    Datadog::Tracing.trace("another boot") {}

    expect(builds).to eq(1)
    expect(Datadog::CI.components(allow_initialization: false)).not_to be_nil
  end

  it "clears initialization guards after failure and preserves the customer exception" do
    builds = 0
    allow(Datadog::CI::Configuration::Components).to receive(:new).and_wrap_original do |method, *args|
      builds += 1
      raise IOError, "construction failed" if builds == 1
      method.call(*args)
    end
    error = RuntimeError.new("customer failure")
    calls = 0

    expect do
      Datadog::Tracing.trace("boot") do
        calls += 1
        raise error
      end
    end.to raise_error { |raised| expect(raised).to equal(error) }
    Datadog::Tracing.trace("next boot") {}

    expect(calls).to eq(1)
    expect(builds).to eq(2)
    expect(Datadog::CI.components(allow_initialization: false)).not_to be_nil
  end

  it "contains initialization errors when the custom logger also fails" do
    logger = Logger.new(File::NULL)
    Datadog.configuration.logger.instance = logger
    allow(logger).to receive(:warn).and_raise(IOError, "logger closed")
    allow(Datadog::CI::Configuration::Components).to receive(:new).and_raise(IOError, "construction failed")
    calls = 0

    expect { Datadog::Tracing.trace("boot") { calls += 1 } }.not_to raise_error
    expect(calls).to eq(1)
    expect(logger).to have_received(:warn)
  ensure
    allow(Datadog::CI::Configuration::Components).to receive(:new).and_call_original
    allow(logger).to receive(:warn).and_call_original
  end

  it "refreshes a bootstrap generation only once at session start" do
    allow(Datadog::CI::Configuration::Components).to receive(:new).and_call_original
    Datadog::Tracing.trace("boot") {}
    original = Datadog::CI.components
    session = Datadog::CI.start_test_session
    replacement = Datadog::CI.components
    Datadog::Tracing.trace("in session") {}

    expect(replacement).not_to equal(original)
    expect(Datadog::CI::Configuration::Components).to have_received(:new).twice
    expect(Datadog::CI.active_test_session).to equal(session)
    session.finish
  end

  it "retires bootstrap components without blocking workers that read the replacement" do
    settings = Datadog::CI::Configuration::RuntimeSettings.new
    settings.ci.enabled = true
    runtime = Datadog::CI::Runtime.new(configuration: settings)
    current_tracing = instance_double(Datadog::CI::TestTracing::Component, configuration_locked?: false)
    next_tracing = instance_double(Datadog::CI::TestTracing::Component, configuration_locked?: false)
    current = instance_double(Datadog::CI::Configuration::Components, test_tracing: current_tracing)
    replacement = instance_double(Datadog::CI::Configuration::Components, test_tracing: next_tracing)
    allow(Datadog::CI::Configuration::Components).to receive(:new).and_return(current, replacement)
    observed = nil
    worker = nil
    allow(current).to receive(:shutdown!) do
      worker = Thread.new { observed = runtime.components(allow_initialization: false) }
      expect(worker.join(2)).to equal(worker)
    end

    runtime.prepare_application_tracing!
    expect(runtime.prepare_test_session(current_tracing)).to equal(next_tracing)
    expect(observed).to equal(replacement)
  ensure
    worker&.kill
    worker&.join
    allow(Datadog::CI::Configuration::Components).to receive(:new).and_call_original
  end
end
