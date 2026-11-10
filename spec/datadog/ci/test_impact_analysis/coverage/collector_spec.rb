# frozen_string_literal: true

require "datadog_ci_native.#{RUBY_VERSION}_#{RUBY_PLATFORM}"
require_relative "../../../../../lib/datadog/ci/test_impact_analysis/coverage/collector"

RSpec.describe Datadog::CI::TestImpactAnalysis::Coverage::Collector do
  let(:root) { Datadog::CI::Git::LocalRepository.root }
  subject(:collector) do
    described_class.new(root: root, ignored_path: nil, threading_mode: :multi, use_allocation_tracing: false)
  end

  after { collector.stop }

  it "merges non-Ruby dependencies with native coverage and serializes existing TIA events" do
    collector.start
    File.read(File.join(root, "Gemfile"))
    coverage = collector.stop

    expect(coverage).to include(File.join(root, "Gemfile") => true, __FILE__ => true)
    files = Datadog::CI::TestImpactAnalysis::Coverage::Files.new(coverage)
    event = Datadog::CI::TestImpactAnalysis::Coverage::Event.new(
      test_id: "3", test_suite_id: "2", test_session_id: "1", files: files
    )
    payload = MessagePack.unpack(MessagePack.pack(event))
    expect(payload.fetch("files")).to include({"filename" => "Gemfile"})
    expect(payload.fetch("span_id")).to eq(3)
  end

  context "when the native collector fails" do
    let(:native) { instance_double(Datadog::CI::TestImpactAnalysis::Coverage::DDCov, start: nil, stop: {}) }

    before do
      allow(Datadog::CI::TestImpactAnalysis::Coverage::DDCov).to receive(:new).and_return(native)
      allow(Datadog.logger).to receive(:warn)
    end

    it "logs a start failure without raising into the test" do
      allow(native).to receive(:start).and_raise("native failure")
      expect { collector.start }.not_to raise_error
      expect(Datadog.logger).to have_received(:warn).with(/native failure/)
    end

    it "retains file dependencies when native coverage fails at stop" do
      collector.start
      File.read(File.join(root, "Gemfile"))
      allow(native).to receive(:stop).and_raise("native failure")
      expect(collector.stop).to include(File.join(root, "Gemfile") => true)
      expect(Datadog.logger).to have_received(:warn).with(/native failure/)
    end
  end
end
