# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/git/local_repository"

RSpec.describe ::Datadog::CI::Git::LocalRepository do
  describe ".root" do
    subject { described_class.root }

    it { is_expected.to eq(Dir.pwd) }

    context "caches the result" do
      before do
        expect(Open3).to receive(:capture2e).never
      end

      it "returns the same result" do
        2.times do
          expect(described_class.root).to eq(Dir.pwd)
        end
      end
    end
  end

  describe ".relative_to_root" do
    subject { described_class.relative_to_root(path) }

    context "when path is nil" do
      let(:path) { nil }

      it { is_expected.to eq("") }
    end

    context "when git root is nil" do
      before do
        allow(described_class).to receive(:root).and_return(nil)
      end

      let(:path) { "foo/bar" }

      it { is_expected.to eq("foo/bar") }
    end

    context "when git root is not nil" do
      context "when path is absolute" do
        before do
          allow(described_class).to receive(:root).and_return("/foo/bar")
        end
        let(:path) { "/foo/bar/baz" }

        it { is_expected.to eq("baz") }
      end

      context "when path is relative" do
        before do
          allow(described_class).to receive(:root).and_return("#{Dir.pwd}/foo/bar")
        end

        let(:path) { "./baz" }

        it { is_expected.to eq("../../baz") }
      end
    end
  end

  describe ".current_folder_name" do
    subject { described_class.current_folder_name }
    let(:path) { "/foo/bar" }

    context "when git root is nil" do
      before do
        allow(described_class).to receive(:root).and_return(nil)
        allow(Dir).to receive(:pwd).and_return(path)
      end

      it { is_expected.to eq("bar") }
    end

    context "when git root is not nil" do
      before do
        allow(described_class).to receive(:root).and_return(path)
      end

      it { is_expected.to eq("bar") }
    end
  end

  describe ".repository_name" do
    subject { described_class.repository_name }

    it { is_expected.to eq("datadog-ci-rb") }

    context "caches the result" do
      before do
        expect(Open3).to receive(:capture2e).never
      end

      it "returns the same result" do
        2.times do
          expect(described_class.root).to eq(Dir.pwd)
        end
      end
    end
  end
end
