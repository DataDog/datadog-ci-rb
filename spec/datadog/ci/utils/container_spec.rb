# frozen_string_literal: true

require "datadog/ci/utils/container"

RSpec.describe Datadog::CI::Utils::Container do
  subject(:container_id) { described_class.container_id }

  let(:docker_id) { "a" * 64 }
  let(:uuid) { "12345678-1234-1234-1234-123456789abc" }
  let(:fargate_id) { "abcdef0123456789abcdef0123456789-1234567890" }
  let(:cgroup) { "12:memory:/docker/#{docker_id}\n" }

  before { allow(File).to receive(:read).with("/proc/self/cgroup").and_return(cgroup) }

  it "detects Docker IDs" do
    expect(container_id).to eq(docker_id)
  end

  ["docker", "cri-containerd", "crio", "libpod"].each do |runtime|
    context "with a #{runtime} systemd scope" do
      let(:cgroup) { "0::/kubepods.slice/kubepods-pod#{uuid}.slice/#{runtime}-#{docker_id}.scope\n" }

      it "detects the final container ID" do
        expect(container_id).to eq(docker_id)
      end
    end
  end

  context "with a UUID container ID" do
    let(:cgroup) { "9:memory:/docker/#{uuid}\n" }

    it { is_expected.to eq(uuid) }
  end

  context "with an underscore UUID container ID" do
    let(:uuid) { "12345678_1234_1234_1234_123456789abc" }
    let(:cgroup) { "9:memory:/docker/#{uuid}\n" }

    it { is_expected.to eq(uuid) }
  end

  context "with a Fargate container ID" do
    let(:cgroup) { "1:name=systemd:/ecs/0123456789abcdef0123456789abcdef/#{fargate_id}\n" }

    it { is_expected.to eq(fargate_id) }
  end

  context "with a compact UUID container ID" do
    let(:uuid) { "12345678123412341234123456789abc" }
    let(:cgroup) { "9:memory:/docker/#{uuid}\n" }

    it { is_expected.to eq(uuid) }
  end

  ["a" * 63, "a" * 65, "abcdef0123456789abcdef0123456789-12345678901"].each do |invalid_id|
    context "with invalid container ID #{invalid_id}" do
      let(:cgroup) { "0::/docker/#{invalid_id}\n" }

      it { is_expected.to be_nil }
    end
  end

  context "with multiple cgroup controllers" do
    let(:cgroup) { "0::/\n12:memory:/docker/#{docker_id}\n" }

    it { is_expected.to eq(docker_id) }
  end

  context "with an ID in a parent path" do
    let(:cgroup) { "0::/ecs/#{docker_id}/task.slice\n" }

    it { is_expected.to be_nil }
  end

  context "with an ID in the controllers field" do
    let(:cgroup) { "1:#{docker_id}:/user.slice/session.scope\n" }

    it { is_expected.to be_nil }
  end

  context "with unrelated text around a hexadecimal ID" do
    let(:cgroup) { "0::/user.slice/unrelated-#{docker_id}-data\n" }

    it { is_expected.to be_nil }
  end

  context "with a hexadecimal process service name" do
    let(:cgroup) { "0::/system.slice/#{docker_id}.service\n" }

    it { is_expected.to be_nil }
  end

  context "with a hexadecimal ID at the cgroup root" do
    let(:cgroup) { "0::/#{docker_id}\n" }

    it { is_expected.to be_nil }
  end

  context "with a malformed cgroup entry" do
    let(:cgroup) { "not-a-hierarchy::/docker/#{docker_id}\n" }

    it { is_expected.to be_nil }
  end

  context "with a missing cgroup file" do
    before { allow(File).to receive(:read).with("/proc/self/cgroup").and_raise(Errno::ENOENT) }

    it { is_expected.to be_nil }
  end
end
