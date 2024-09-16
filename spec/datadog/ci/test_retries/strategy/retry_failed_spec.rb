require_relative "../../../../../lib/datadog/ci/test_retries/strategy/retry_new"

RSpec.describe Datadog::CI::TestRetries::Strategy::RetryFailed do
  include_context "Telemetry spy"

  let(:enabled) { true }

  let(:remote_flaky_test_retries_enabled) { false }
  let(:max_attempts) { 1 }
  let(:total_limit) { 12 }

  let(:library_settings) do
    instance_double(
      Datadog::CI::Remote::LibrarySettings,
      flaky_test_retries_enabled?: remote_flaky_test_retries_enabled
    )
  end

  let(:tracer_span) { Datadog::Tracing::SpanOperation.new("session") }
  let(:test_session) do
    Datadog::CI::TestSession.new(tracer_span)
  end

  subject(:strategy) do
    described_class.new(
      enabled: enabled,
      max_attempts: max_attempts,
      total_limit: total_limit
    )
  end

  describe "#configure" do
    subject { strategy.configure(library_settings, test_session) }

    context "when flaky test retries are enabled" do
      let(:remote_flaky_test_retries_enabled) { true }

      it "enables retrying failed tests" do
        subject

        expect(strategy.enabled).to be true
      end
    end

    context "when flaky test retries are disabled" do
      let(:remote_flaky_test_retries_enabled) { false }

      it "disables retrying failed tests" do
        subject

        expect(strategy.enabled).to be false
      end
    end

    context "when flaky test retries are disabled in local settings" do
      let(:enabled) { false }
      let(:remote_flaky_test_retries_enabled) { true }

      it "disables retrying failed tests even if it's enabled remotely" do
        subject

        expect(strategy.enabled).to be false
      end
    end
  end
end
