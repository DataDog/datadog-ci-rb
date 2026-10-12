# frozen_string_literal: true

require "open3"

RSpec.describe Datadog::CI::Configuration::Reconfiguration do
  include_context "CI mode activated"

  let(:service_name) { "original-service" }

  it "allows configuration before a test session starts" do
    original = Datadog.send(:components)

    Datadog.configure { |c| c.service = "new-service" }

    expect(Datadog.configuration.service).to eq("new-service")
    expect(Datadog.send(:components)).not_to equal(original)
  end

  it "does not initialize components just to check whether configuration is allowed" do
    Datadog.send(:reset!)
    expect(Datadog::Core::Configuration::Components).to receive(:new).once.and_call_original

    Datadog.configure { |c| c.ci.enabled = false }
  end

  it "allows configuration when tracing components were initialized before CI was loaded" do
    output, status = Open3.capture2e(RbConfig.ruby, "-Ilib", "-e", <<~RUBY)
      require "datadog"
      Datadog.configure { |c| c.telemetry.enabled = false }
      require "datadog/ci"
      Datadog.configure { |c| c.service = "configured-after-ci-load" }
      abort "Configuration was ignored" unless Datadog.configuration.service == "configured-after-ci-load"
    RUBY

    expect(status.success?).to be(true), output
  end

  it "warns and skips the configuration block as soon as a session starts" do
    original = Datadog.send(:components)
    session = Datadog::CI.start_test_session
    expect(Datadog.logger).to receive(:warn).with(/Datadog.configure ignored.*Move Datadog.configure/)

    result = Datadog.configure do |c|
      c.service = "new-service"
      c.ci.enabled = false
    end

    expect(result).to equal(Datadog.configuration)
    expect(Datadog.configuration.service).to eq("original-service")
    expect(Datadog.configuration.ci.enabled).to be(true)
    expect(Datadog.send(:components)).to equal(original)
    expect(Datadog::CI.active_test_session).to equal(session)
  end

  it "keeps configuration locked when session startup fails" do
    allow(DRb).to receive(:start_service).and_raise(DRb::DRbConnError, "DRb startup failed")

    expect { Datadog::CI.start_test_session }.to raise_error(DRb::DRbConnError, "DRb startup failed")
    expect(Datadog::CI.active_test_session).to be_nil

    Datadog.configure { |c| c.service = "ignored-service" }

    expect(Datadog.configuration.service).to eq("original-service")
  end

  it "keeps configuration locked when setup fails after creating a session" do
    original = Datadog.send(:components)
    allow(original.ci_remote).to receive(:configure).and_raise("Remote configuration failed")

    expect { Datadog::CI.start_test_session }.to raise_error("Remote configuration failed")
    session = Datadog::CI.active_test_session
    expect(session).not_to be_nil

    Datadog.configure { |c| c.service = "ignored-service" }

    expect(Datadog.configuration.service).to eq("original-service")
    expect(Datadog.send(:components)).to equal(original)
    expect(Datadog::CI.active_test_session).to equal(session)
  end

  it "allows reconfiguration after the owning session finishes, including empty sessions" do
    original = Datadog.send(:components)
    Datadog::CI.start_test_session.finish

    Datadog.configure { |c| c.service = "next-session-service" }

    expect(Datadog.send(:components)).not_to equal(original)
    expect(Datadog::CI.start_test_session.service).to eq("next-session-service")

    Datadog.configure { |c| c.ci.enabled = false }
    expect(Datadog.configuration.ci.enabled).to be(true)
  end

  it "allows reconfiguration after tests traced without a session" do
    original = Datadog.send(:components)
    Datadog::CI.trace_test("standalone", "suite") { |test| test.passed! }

    Datadog.configure { |c| c.ci.enabled = false }

    expect(Datadog.configuration.ci.enabled).to be(false)
    expect(Datadog.send(:components)).not_to equal(original)
  end

  context "with test management enabled and Auto Test Retry disabled remotely" do
    let(:test_management_enabled) { true }
    let(:test_properties) { {"suite.quarantined." => {"quarantined" => true}} }

    it "preserves session IDs, quarantine and retry decisions through repeated setup and cleanup" do
      original = Datadog.send(:components)
      session = Datadog::CI.start_test_session
      test_module = Datadog::CI.start_test_module("rspec")
      suite = Datadog::CI.start_test_suite("suite")

      3.times do
        Datadog.configure { |c| c.service = "setup-service" }
        attempts = 0

        Datadog.send(:components).test_retries.with_retries do
          Datadog::CI.trace_test("quarantined", "suite") do |test|
            attempts += 1
            test.failed!
            expect(test.quarantined?).to be(true)
            expect(test.test_session_id).to eq(session.id.to_s)
            expect(test.test_module_id).to eq(test_module.id.to_s)
            expect(test.test_suite_id).to eq(suite.id.to_s)
          end
        end
        Datadog.configure { |c| c.service = "cleanup-service" }

        expect(attempts).to eq(1)
        expect(Datadog.send(:components)).to equal(original)
      end

      suite.finish
      test_module.finish
      session.finish

      Datadog.configure { |c| c.ci.enabled = false }
      expect(Datadog.configuration.ci.enabled).to be(false)
    end
  end

  context "with CI disabled" do
    let(:ci_enabled) { false }

    it "allows repeated configuration during ordinary tracing" do
      Datadog::Tracing.trace("ordinary") do
        Datadog.configure { |c| c.service = "first-service" }
        Datadog.configure { |c| c.service = "second-service" }
      end

      expect(Datadog.configuration.service).to eq("second-service")
    end
  end

  context "in forked processes", if: Process.respond_to?(:fork) do
    it "inherits protection before the first child test" do
      Datadog::CI.start_test_session

      expect_in_fork do
        original = Datadog.send(:components)
        Datadog.configure { |c| c.ci.enabled = false }

        expect(Datadog.send(:components)).to equal(original)
        expect(Datadog.configuration.ci.enabled).to be(true)
      end
    end

    it "allows configuration in a process forked before session startup" do
      expect_in_fork do
        Datadog.configure { |c| c.service = "worker-service" }
        expect(Datadog.configuration.service).to eq("worker-service")

        Datadog::CI.start_test_session
        Datadog.configure { |c| c.service = "ignored-service" }
        expect(Datadog.configuration.service).to eq("worker-service")
      end
    end

    it "allows worker setup, then protects a worker joined to a distributed session" do
      session = test_tracing.start_test_session(distributed: true)
      context_uri = test_tracing.context_service_uri

      expect_in_fork do
        # Emulate a fresh worker using the real DRb service in the parent process.
        DRb.stop_service
        Datadog.send(:reset!)
        Datadog.configure do |c|
          c.ci.enabled = true
          c.ci.git_metadata_upload_enabled = false
          c.ci.test_visibility_drb_server_uri = context_uri
        end
        Datadog.configure { |c| c.service = "worker-service" }
        original = Datadog.send(:components)
        worker_session = Datadog::CI.start_test_session
        expect(worker_session.id).to eq(session.id)
        worker_tracing = Datadog::CI.send(:test_tracing)
        expect(worker_tracing.shared_tags).to include("test_session.name" => worker_session.name)

        worker_test = Datadog::CI.start_test("worker test", "worker suite")
        expect(worker_tracing.shared_tags).not_to be_empty
        expect(worker_tracing.shared_tags).to include("git.repository_url" => worker_test.git_repository_url)
        expect(worker_tracing.shared_tags).to include("test_session.name" => worker_session.name)
        worker_test.finish

        Datadog.configure { |c| c.ci.enabled = false }
        expect(Datadog.send(:components)).to equal(original)
        expect(Datadog.configuration.ci.enabled).to be(true)
      end
    end
  end
end
