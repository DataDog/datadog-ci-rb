# frozen_string_literal: true

require_relative "../../../../../lib/datadog/ci/itr/coverage/writer"
require_relative "../../../../../lib/datadog/ci/itr/coverage/transport"

RSpec.describe Datadog::CI::ITR::Coverage::Writer do
  subject(:writer) { described_class.new(transport: transport, options: options) }

  let(:options) { {} }
  let(:transport) { instance_double(Datadog::CI::ITR::Coverage::Transport) }
  before do
    allow(transport).to receive(:send_events).and_return([])
  end

  after { writer.stop(true, 0) }

  let(:buffer_klass) do
    if PlatformHelpers.jruby?
      Datadog::Core::Buffer::ThreadSafe
    else
      Datadog::Core::Buffer::CRuby
    end
  end

  it { expect(writer).to be_a_kind_of(Datadog::Core::Workers::Queue) }
  it { expect(writer).to be_a_kind_of(Datadog::Core::Workers::Polling) }

  describe "#initialize" do
    context "defaults" do
      it do
        is_expected.to have_attributes(
          enabled?: true,
          fork_policy: Datadog::Core::Workers::Async::Thread::FORK_POLICY_RESTART,
          buffer: kind_of(buffer_klass)
        )
      end
    end

    context "given :enabled" do
      let(:options) { {enabled: enabled} }

      context "as false" do
        let(:enabled) { false }

        it { expect(writer.enabled?).to be false }
      end

      context "as true" do
        let(:enabled) { true }

        it { expect(writer.enabled?).to be true }
      end

      context "as nil" do
        let(:enabled) { nil }

        it { expect(writer.enabled?).to be false }
      end
    end
    context "given :interval" do
      let(:options) { {interval: interval} }
      let(:interval) { double("interval") }

      it { expect(writer.loop_base_interval).to be interval }
    end

    context "given :back_off_ratio" do
      let(:options) { {back_off_ratio: back_off_ratio} }
      let(:back_off_ratio) { double("back_off_ratio") }

      it { expect(writer.loop_back_off_ratio).to be back_off_ratio }
    end

    context "given :back_off_max" do
      let(:options) { {back_off_max: back_off_max} }
      let(:back_off_max) { double("back_off_max") }

      it { expect(writer.loop_back_off_max).to be back_off_max }
    end

    context "given :buffer_size" do
      let(:options) { {buffer_size: buffer_size} }
      let(:buffer_size) { double("buffer_size") }
      let(:buffer) { instance_double(buffer_klass) }

      before do
        expect(buffer_klass).to receive(:new)
          .with(buffer_size)
          .and_return(buffer)
      end

      it { expect(writer.buffer).to be buffer }
    end
  end

  describe "#perform" do
    subject(:perform) { writer.perform }

    after { writer.stop(true, 0) }

    it "starts a worker thread" do
      perform

      expect(writer.send(:worker)).to be_a_kind_of(Thread)
      expect(writer).to have_attributes(
        run_async?: true,
        running?: true,
        started?: true,
        forked?: false,
        fork_policy: :restart,
        result: nil
      )
    end
  end

  describe "#enqueue" do
    subject(:enqueue) { writer.enqueue(event) }

    let(:event) { double("event") }

    before do
      allow(writer.buffer).to receive(:push)
      enqueue
    end

    it { expect(writer.buffer).to have_received(:push).with(event) }
  end

  describe "#dequeue" do
    subject(:dequeue) { writer.dequeue }

    let(:events) { [double("event")] }

    before do
      allow(writer.buffer).to receive(:pop)
        .and_return(events)
    end

    it { is_expected.to eq(events) }
  end

  describe "#work_pending?" do
    subject(:work_pending?) { writer.work_pending? }

    context "when the buffer is empty" do
      it { is_expected.to be false }
    end

    context "when the buffer is not empty" do
      let(:event) { double("event") }

      before { writer.enqueue(event) }

      it { is_expected.to be true }
    end
  end

  describe "#write" do
    subject(:write) { writer.write(event) }

    let(:event) { double("event") }

    it "starts a worker thread & queues the event" do
      expect(writer.buffer).to receive(:push)
        .with(event)

      expect { write }.to change { writer.running? }
        .from(false)
        .to(true)
    end
  end
end
