# frozen_string_literal: true

require "spec_helper"

RSpec.describe Datadog::CI::Runtime do
  include_context "CI mode activated"

  let(:flaky_test_retries_enabled) { true }
  let(:service_name) { "initial-service" }

  before do
    Datadog.configure do |settings|
      settings.telemetry.enabled = false
      settings.remote.enabled = false
    end
  end

  it "keeps the CI session and retry state when application tracing resets during an attempt" do
    session = Datadog::CI.start_test_session
    test_module = Datadog::CI.start_test_module("module")
    suite = Datadog::CI.start_test_suite("suite")
    components = Datadog::CI.components
    attempts = []

    components.test_retries.with_retries do
      Datadog::CI.trace_test("example", "suite") do |test|
        attempts << test
        expect(test.test_session_id).to eq(session.id.to_s)
        expect(test.test_suite_id).to eq(suite.id.to_s)
        if attempts.length == 1
          test.failed!
          Datadog.send(:reset!)
        else
          test.passed!
        end
      end
    end

    expect(attempts.length).to eq(2)
    expect(attempts.last.is_retry?).to be(true)
    expect(attempts.last.get_tag("test.final_status")).to eq("pass")
    expect(Datadog::CI.components).to equal(components)
    expect(Datadog::CI.active_test_session).to equal(session)
    suite.finish
    test_module.finish
    session.finish
  end

  it "allows application reconfiguration and shutdown without replacing CI components" do
    session = Datadog::CI.start_test_session
    components = Datadog::CI.components

    Datadog.configure { |settings| settings.service = "application-service" }
    expect(Datadog.configuration.service).to eq("application-service")
    expect(Datadog::CI.configuration.service).to eq("initial-service")
    Datadog.shutdown!

    expect(Datadog::CI.components).to equal(components)
    expect(Datadog::CI.active_test_session).to equal(session)
    Datadog::CI.trace_test("after shutdown", "suite") { |test| test.passed! }
    session.finish
    expect(test_spans.map(&:name)).to include("after shutdown")
  end

  it "imports a direct legacy service assignment before evaluating session defaults" do
    Datadog.configuration.service = "direct-service"
    Datadog.configuration.env = "direct-env"
    session = Datadog::CI.start_test_session

    expect(session.service).to eq("direct-service")
    expect(Datadog::CI.configuration.env).to eq("direct-env")
    session.finish
  end

  it "keeps explicit CI settings ahead of imported application defaults" do
    Datadog::CI.configure do |settings|
      settings.service = "ci-service"
      settings.env = "ci-env"
    end
    Datadog.configure do |settings|
      settings.service = "application-service"
      settings.env = "application-env"
    end
    session = Datadog::CI.start_test_session

    expect(session.service).to eq("ci-service")
    expect(Datadog::CI.configuration.env).to eq("ci-env")
    expect(Datadog.configuration.service).to eq("application-service")
    session.finish
  end

  it "rebuilds inactive CI components after legacy configuration changes" do
    previous = Datadog::CI.components
    Datadog.configure { |settings| settings.service = "next-service" }

    expect(Datadog::CI.components).not_to equal(previous)
    session = Datadog::CI.start_test_session
    expect(session.service).to eq("next-service")
    session.finish
  end

  it "uses its own reset lifecycle" do
    previous = Datadog::CI.components
    Datadog::CI.start_test_session
    Datadog::CI.reset!

    expect(Datadog::CI.components(allow_initialization: false)).to be_nil
    expect(Datadog::CI.active_test_session).to be_nil
    expect(Datadog::CI.components).not_to equal(previous)
  end

  it "uses the configured logger and debug level" do
    logger = Logger.new(File::NULL)
    Datadog::CI.configure { |settings| settings.logger.instance = logger }
    expect(Datadog::CI.logger).to equal(logger)
    Datadog::CI.configure do |settings|
      settings.logger.instance = nil
      settings.logger.level = Logger::ERROR
    end
    expect(Datadog::CI.logger.level).to eq(Logger::ERROR)
    Datadog::CI.configure { |settings| settings.diagnostics.debug = true }
    expect(Datadog::CI.logger.level).to eq(Logger::DEBUG)
  end
end

RSpec.describe "CI logging before component startup" do
  it "uses a logger configured through the legacy API" do
    logger = Logger.new(File::NULL)
    Datadog.configure { |settings| settings.logger.instance = logger }

    expect(Datadog::CI.components(allow_initialization: false)).to be_nil
    expect(Datadog::CI.logger).to equal(logger)
    expect(Datadog::CI.components(allow_initialization: false)).to be_nil
  end
end
