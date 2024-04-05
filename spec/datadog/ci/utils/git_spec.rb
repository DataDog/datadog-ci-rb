RSpec.describe ::Datadog::CI::Utils::Git do
  describe ".normalize_ref" do
    subject { described_class.normalize_ref(ref) }

    context "when input is nil" do
      let(:ref) { nil }

      it { is_expected.to be_nil }
    end

    context "when input is github ref" do
      let(:ref) { "refs/heads/master" }

      it "strips everything out except ref name" do
        is_expected.to eq("master")
      end
    end

    context "when input includes tags" do
      let(:ref) { "refs/heads/tags/0.1.0" }

      it "strips everything out except ref name" do
        is_expected.to eq("0.1.0")
      end
    end
  end

  describe ".is_git_tag?" do
    subject { described_class.is_git_tag?(ref) }

    context "when input is nil" do
      let(:ref) { nil }

      it { is_expected.to be_falsey }
    end

    context "when input is a branch" do
      let(:ref) { "refs/heads/master" }

      it { is_expected.to be_falsey }
    end

    context "when input includes tags" do
      let(:ref) { "refs/heads/tags/0.1.0" }

      it { is_expected.to be_truthy }
    end
  end
end
