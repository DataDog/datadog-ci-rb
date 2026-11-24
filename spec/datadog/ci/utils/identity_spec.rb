# frozen_string_literal: true

require "spec_helper"
require "timeout"
require "datadog/ci/utils/identity"

RSpec.describe Datadog::CI::Utils::Identity do
  it "preserves runtime identity during application PID mocks" do
    original = described_class.id
    allow(Process).to receive(:pid).and_return(Process.pid + 1)

    expect(described_class.id).to eq(original)
  end

  it "refreshes process and runtime identities after a real fork" do
    skip "Fork is unavailable" unless Process.respond_to?(:fork)

    original = described_class.id
    reader, writer = IO.pipe
    child = Process.fork do
      reader.close
      writer.write("#{described_class.pid}:#{described_class.id}")
      writer.close
      Process.exit!(0)
    end
    writer.close
    child_pid, child_id = Timeout.timeout(5) { reader.read }.split(":", 2)
    expected_pid = child
    _, status = Timeout.timeout(5) { Process.wait2(child) }
    child = nil

    expect(status.success?).to be(true)
    expect(child_pid.to_i).to eq(expected_pid)
    expect(child_id).not_to eq(original)
    expect(described_class.pid).to eq(Process.pid)
    expect(described_class.id).to eq(original)
  ensure
    if child
      Process.kill("KILL", child)
      Process.wait(child)
    end
    reader&.close unless reader&.closed?
    writer&.close unless writer&.closed?
  end
end
