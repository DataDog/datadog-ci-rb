# frozen_string_literal: true

require_relative "../../../lib/datadog/ci/worker"

RSpec.describe Datadog::CI::Worker do
  let(:task) { spy("task") }
  let(:work) { task.call }

  subject(:worker) { described_class.new { work } }

  describe "#perform" do
    it "executes the task" do
      worker.perform
      worker.stop

      expect(task).to have_received(:call)
    end
  end

  describe "#done?" do
    context "when the worker has not started" do
      it { is_expected.not_to be_done }
    end

    context "when the worker has started" do
      context "when the worker is running" do
        let(:queue) { Thread::Queue.new }
        subject(:worker) { described_class.new { queue.pop } }

        it do
          worker.perform
          is_expected.not_to be_done

          queue << :done
          worker.stop

          is_expected.to be_done
        end
      end

      context "when the worker has stopped" do
        it do
          worker.perform
          worker.stop

          is_expected.to be_done
        end
      end
    end
  end

  describe "#wait_until_done" do
    it "waits until the worker is done" do
      worker.perform
      worker.wait_until_done

      expect(worker).to be_done
    end
  end
end
