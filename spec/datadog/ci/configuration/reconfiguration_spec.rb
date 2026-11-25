# frozen_string_literal: true

require "open3"
require "tmpdir"

RSpec.describe Datadog::CI::Configuration::Reconfiguration do
  include_context "CI mode activated"

  let(:service_name) { "original-service" }

  it "imports configuration blocks before a test session starts" do
    Datadog.configure do |c|
      c.service = "new-service"
      c.env = "new-environment"
    end

    session = Datadog::CI.start_test_session

    expect(session.service).to eq("new-service")
    expect(Datadog::CI.configuration.env).to eq("new-environment")
  end

  it "imports direct configuration writes before a test session starts" do
    Datadog.configuration.service = "direct-service"
    Datadog.configuration.tags = {"custom-tag" => "custom-value"}

    session = Datadog::CI.start_test_session

    expect(session.service).to eq("direct-service")
    expect(Datadog::CI.configuration.tags).to include("custom-tag" => "custom-value")
  end

  it "preserves explicit independent configuration over legacy defaults" do
    Datadog::CI.configure { |c| c.service = "independent-service" }
    Datadog.configure { |c| c.service = "application-service" }

    expect(Datadog::CI.start_test_session.service).to eq("independent-service")
    expect(Datadog.configuration.service).to eq("application-service")
  end

  it "does not build CI components to notify a configuration change" do
    Datadog::CI.reset!
    allow(Datadog::CI::Configuration::Components).to receive(:new).and_call_original

    Datadog.configure { |c| c.ci.enabled = false }

    expect(Datadog::CI::Configuration::Components).not_to have_received(:new)
  end

  it "keeps existing configuration calls available when the tracer is absent" do
    Dir.mktmpdir("independent-ci-bundle") do |directory|
      gemfile = File.join(directory, "Gemfile")
      File.write(gemfile, "source \"https://rubygems.org\"\ngem \"msgpack\"\ngem \"drb\"\n")
      code = <<~RUBY
        require "datadog/ci"
        abort "The optional tracer was loaded" if defined?(Datadog::Tracing)
        Datadog.configure do |c|
          c.service = "standalone-service"
          c.env = "standalone-environment"
          c.tags = {"custom-tag" => "custom-value"}
          c.ci.enabled = false
        end
        abort "Legacy configuration was lost" unless Datadog::CI.configuration.service == "standalone-service"
        abort "Environment was lost" unless Datadog.configuration.env == "standalone-environment"
        abort "Tags were lost" unless Datadog.configuration.tags["custom-tag"] == "custom-value"
      RUBY

      environment = {"BUNDLE_GEMFILE" => gemfile, "GEM_HOME" => Gem.dir, "GEM_PATH" => Gem.path.join(File::PATH_SEPARATOR)}
      output, status = Bundler.with_unbundled_env do
        Open3.capture2e(environment, RbConfig.ruby, "-rbundler/setup", "-Ilib", "-e", code)
      end
      expect(status.success?).to be(true), output
    end
  end

  it "supports loading CI after the tracer already initialized" do
    output, status = Open3.capture2e(RbConfig.ruby, "-Ilib", "-e", <<~RUBY)
      require "datadog"
      Datadog.configure { |c| c.telemetry.enabled = false }
      require "datadog/ci"
      Datadog.configure { |c| c.service = "configured-after-ci-load" }
      abort "Legacy configuration was lost" unless Datadog::CI.configuration.service == "configured-after-ci-load"
    RUBY

    expect(status.success?).to be(true), output
  end

  it "allows tracer reconfiguration without replacing an active CI session" do
    session = Datadog::CI.start_test_session
    original = Datadog::CI.components

    Datadog.configure { |c| c.service = "application-service" }

    expect(Datadog.configuration.service).to eq("application-service")
    expect(Datadog::CI.components).to equal(original)
    expect(Datadog::CI.active_test_session).to equal(session)
    expect(session.service).to eq("original-service")
  end

  it "keeps the CI session and configuration when the application tracer resets" do
    session = Datadog::CI.start_test_session
    original = Datadog::CI.components

    Datadog.send(:reset!)

    expect(Datadog::CI.components).to equal(original)
    expect(Datadog::CI.active_test_session).to equal(session)
    expect(Datadog::CI.configuration.service).to eq("original-service")
  end

  it "allows tracer configuration after CI session startup fails" do
    allow(DRb).to receive(:start_service).and_raise(DRb::DRbConnError, "DRb startup failed")

    expect { Datadog::CI.start_test_session }.to raise_error(DRb::DRbConnError, "DRb startup failed")
    Datadog.configure { |c| c.service = "application-service" }

    expect(Datadog.configuration.service).to eq("application-service")
  end

  it "imports new configuration after the owning session finishes" do
    original = Datadog::CI.components
    Datadog::CI.start_test_session.finish
    Datadog.configure { |c| c.service = "next-session-service" }

    expect(Datadog::CI.components).not_to equal(original)
    expect(Datadog::CI.start_test_session.service).to eq("next-session-service")
  end

  context "with test management enabled and Auto Test Retry disabled remotely" do
    let(:test_management_enabled) { true }
    let(:test_properties) { {"suite.quarantined." => {"quarantined" => true}} }

    it "preserves session IDs and policy through application tracer resets" do
      original = Datadog::CI.components
      session = Datadog::CI.start_test_session
      test_module = Datadog::CI.start_test_module("rspec")
      suite = Datadog::CI.start_test_suite("suite")

      3.times do
        Datadog.configure { |c| c.service = "setup-service" }
        attempts = 0

        Datadog::CI.components.test_retries.with_retries do
          Datadog::CI.trace_test("quarantined", "suite") do |test|
            attempts += 1
            test.failed!
            expect(test.quarantined?).to be(true)
            expect(test.test_session_id).to eq(session.id.to_s)
            expect(test.test_module_id).to eq(test_module.id.to_s)
            expect(test.test_suite_id).to eq(suite.id.to_s)
          end
        end
        Datadog.send(:reset!)

        expect(attempts).to eq(1)
        expect(Datadog::CI.components).to equal(original)
      end

      suite.finish
      test_module.finish
      session.finish
    end
  end

  context "in forked processes", if: Process.respond_to?(:fork) do
    it "keeps inherited CI state when the worker reconfigures its application tracer" do
      session = Datadog::CI.start_test_session

      expect_in_fork do
        original = Datadog::CI.components
        Datadog.configure { |c| c.service = "worker-application" }

        expect(Datadog.configuration.service).to eq("worker-application")
        expect(Datadog::CI.components).to equal(original)
        expect(Datadog::CI.active_test_session.id).to eq(session.id)
      end
    end

    it "preserves a distributed session while the worker changes its application tracer" do
      session = test_tracing.start_test_session(distributed: true)
      context_uri = test_tracing.context_service_uri

      expect_in_fork do
        DRb.stop_service
        Datadog::CI.reset!
        Datadog.send(:reset!)
        Datadog.configure do |c|
          c.ci.enabled = true
          c.ci.git_metadata_upload_enabled = false
          c.ci.test_visibility_drb_server_uri = context_uri
          c.service = "worker-service"
        end
        worker_session = Datadog::CI.start_test_session
        original = Datadog::CI.components
        worker_test = Datadog::CI.start_test("worker test", "worker suite")
        worker_test.finish

        Datadog.configure { |c| c.service = "worker-application" }

        expect(worker_session.id).to eq(session.id)
        expect(Datadog::CI.components).to equal(original)
        expect(Datadog::CI.active_test_session.id).to eq(session.id)
        expect(Datadog.configuration.service).to eq("worker-application")
      end
    end

    it "allows independent configuration in a worker forked before session startup" do
      expect_in_fork do
        Datadog.configure { |c| c.service = "worker-service" }
        session = Datadog::CI.start_test_session
        Datadog.configure { |c| c.service = "worker-application" }

        expect(session.service).to eq("worker-service")
        expect(Datadog.configuration.service).to eq("worker-application")
        expect(Datadog::CI.active_test_session).to equal(session)
      end
    end
  end
end
