require_relative "../../../../lib/datadog/ci/utils/bundle"

RSpec.describe Datadog::CI::Utils::Bundle do
  describe ".location" do
    subject { described_class.location }
    let(:bundle_path) { "/path/to/repo/vendor/bundle" }
    let(:git_root) { "/path/to/repo" }

    before do
      allow(Bundler).to receive(:bundle_path).and_return(bundle_path)
      allow(Datadog::CI::Git::LocalRepository).to receive(:root).and_return(git_root)
    end

    context "when Bundler.bundle_path is located under the git root" do
      it { is_expected.to eq(bundle_path) }
    end

    context "when Bundler.bundle_path is not located under the git root" do
      let(:git_root) { "/path/to/different/repo" }

      it { is_expected.to be_nil }
    end

    context "when an exception is raised" do
      before do
        allow(Bundler).to receive(:bundle_path).and_raise(StandardError.new("Failed to find bundle path"))
        allow(Datadog.logger).to receive(:warn)
        allow(File).to receive(:directory?).and_return(false)
      end

      it "logs a warning and tries other possible bundle locations" do
        expect(Datadog.logger).to receive(:warn).with(/Failed to find bundled gems location/)

        expect(Datadog::CI::Utils::Bundle.location).to be_nil
      end

      context "when one of the possible bundle locations exists" do
        it "returns the existing bundle location" do
          allow(File).to receive(:directory?).with(File.join(git_root, "vendor/bundle")).and_return(true)

          expect(Datadog::CI::Utils::Bundle.location).to eq("/path/to/repo/vendor/bundle")
        end
      end
    end
  end
end
