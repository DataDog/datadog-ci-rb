RSpec.describe ::Datadog::CI::Utils::Git do
  describe ".valid_commit_sha?" do
    subject { described_class.valid_commit_sha?(sha) }

    context "when input is nil" do
      let(:sha) { nil }

      it { is_expected.to be_falsey }
    end

    context "when input is a valid sha" do
      let(:sha) { "c7f893648f656339f62fb7b4d8a6ecdf7d063835" }

      it { is_expected.to be_truthy }
    end

    context "when input is a valid sha256" do
      let(:sha) { "1b9affbba072ba2e923797d3b2050b9b9c8baacf696f84ac9940282b5568c547" }

      it { is_expected.to be_truthy }
    end

    context "when input is a several valid shas separated by newline" do
      let(:sha) { "c7f893648f656339f62fb7b4d8a6ecdf7d063835\nc7f893648f656339f62fb7b4d8a6ecdf7d063835" }

      it { is_expected.to be_falsey }
    end

    context "when input is a an invalid sha" do
      let(:sha) { "c7f893648g656339f62fb7b4d8a6ecdf7d063835" }

      it { is_expected.to be_falsey }
    end

    context "when input is too short to be valid" do
      let(:sha) { "c7f893648f656339f62fb7b4d8a6ecdf7d06383" }

      it { is_expected.to be_falsey }
    end
  end

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
