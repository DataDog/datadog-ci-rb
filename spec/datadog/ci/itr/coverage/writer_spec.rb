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

  describe "#stop" do
    before { skip if PlatformHelpers.jruby? }

    subject(:stop) { writer.stop }

    shared_context "shuts down the worker" do
      before do
        expect(writer.buffer).to receive(:close).at_least(:once)

        # Do this to prevent cleanup from breaking the test
        allow(writer).to receive(:join)
          .with(0)
          .and_return(true)

        allow(writer).to receive(:join)
          .with(described_class::DEFAULT_SHUTDOWN_TIMEOUT)
          .and_return(true)
      end
    end

    context "when the worker has not been started" do
      before do
        expect(writer.buffer).to_not receive(:close)
        allow(writer).to receive(:join)
          .with(described_class::DEFAULT_SHUTDOWN_TIMEOUT)
          .and_return(true)
      end

      it { is_expected.to be false }
    end

    context "when the worker has been started" do
      include_context "shuts down the worker"

      before do
        writer.perform
        try_wait_until { writer.running? && writer.run_loop? }
      end

      it { is_expected.to be true }
    end

    context "called multiple times with graceful stop" do
      include_context "shuts down the worker"

      before do
        writer.perform
        try_wait_until { writer.running? && writer.run_loop? }
      end

      it do
        expect(writer.stop).to be true
        try_wait_until { !writer.running? }
        expect(writer.stop).to be false
      end
    end

    context "given force_stop: true" do
      subject(:stop) { writer.stop(true) }

      context "and the worker does not gracefully stop" do
        before do
          # Make it ignore graceful stops
          expect(writer.buffer).to receive(:close)
          allow(writer).to receive(:stop_loop).and_return(false)
          allow(writer).to receive(:join).and_return(nil)
        end

        context "after the worker has been started" do
          before { writer.perform }

          it do
            is_expected.to be true

            # Give thread time to be terminated
            try_wait_until { !writer.running? }

            expect(writer.run_async?).to be false
            expect(writer.running?).to be false
          end
        end
      end
    end

    context "given shutdown_timeout" do
      let(:options) { {shutdown_timeout: 1000} }
      include_context "shuts down the worker"

      context "and the worker has been started" do
        before do
          expect(writer).to receive(:join).with(1000).and_return(true)

          writer.perform
          try_wait_until { writer.running? && writer.run_loop? }
        end

        it { is_expected.to be true }
      end
    end
  end
  describe "integration tests" do
    describe "forking" do
      before { skip "Fork not supported on current platform" unless Process.respond_to?(:fork) }
      let(:flushed_events) { [] }

      context "when the process forks and an event is written" do
        let(:events) { [double("event"), double("event2")] }

        before do
          allow(writer).to receive(:after_fork)
            .and_call_original
          allow(writer.transport).to receive(:send_events)
            .and_return([])
        end

        after { expect(writer.stop).to be_truthy }

        it "does not drop any events" do
          # Start writer in main process
          writer.perform

          expect_in_fork do
            # Queue up events, wait for worker to process them.
            events.each { |event| writer.write(event) }
            try_wait_until(seconds: 3) { !writer.work_pending? }
            writer.stop

            # Verify state of the writer
            expect(writer).to have_received(:after_fork).once
            expect(writer.buffer).to be_empty
            expect(writer.error?).to be false

            expect(writer.transport).to have_received(:send_events).at_most(events.length).times do |events|
              flushed_events.concat(events)
            end

            expect(events).to_not be_empty
            expect(events).to have(events.length).items
            expect(events).to include(*events)
          end
        end
      end
    end
  end
end
