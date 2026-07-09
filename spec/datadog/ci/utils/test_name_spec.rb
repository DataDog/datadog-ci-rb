# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/utils/test_name"

RSpec.describe Datadog::CI::Utils::TestName do
  describe ".normalize" do
    subject(:normalize) { described_class.normalize(name) }

    context "when name is nil" do
      let(:name) { nil }

      it { is_expected.to be_nil }
    end

    context "when name is not a string" do
      let(:name) { :minitest }

      it { is_expected.to eq(:minitest) }
    end

    context "when name does not contain generated Ruby values" do
      let(:name) { "User logs in with a valid password" }

      it { is_expected.to eq(name) }
    end

    it "normalizes Ruby object inspections" do
      expect(described_class.normalize("is expected to eq #<User:0x000000010 @id=1>"))
        .to eq("is expected to eq OBJECT:User")
      expect(described_class.normalize("is expected to eq #<Admin::User:0x000000010 @id=1>"))
        .to eq("is expected to eq OBJECT:Admin::User")
    end

    it "normalizes date values" do
      expect(described_class.normalize("is expected to eq #<Date: 2026-07-09 ((2461231j,0s,0n),+0s,2299161j)>"))
        .to eq("is expected to eq DATE")
      expect(described_class.normalize("expires on 2026-07-09"))
        .to eq("expires on DATE")
      expect(described_class.normalize("expires on Thu, 09 Jul 2026"))
        .to eq("expires on DATE")
    end

    it "normalizes time values" do
      expect(described_class.normalize("created at 2026-07-09 10:11:12 +0200"))
        .to eq("created at TIME")
      expect(described_class.normalize("created at 2026-07-09T10:11:12Z"))
        .to eq("created at TIME")
      expect(described_class.normalize("created at Thu, 09 Jul 2026 10:11:12 CEST"))
        .to eq("created at TIME")
    end

    it "does not normalize plain class names" do
      expect(described_class.normalize("is expected to eq User"))
        .to eq("is expected to eq User")
      expect(described_class.normalize("is expected to be a Time"))
        .to eq("is expected to be a Time")
      expect(described_class.normalize("is expected to be_kind_of Admin::User"))
        .to eq("is expected to be_kind_of Admin::User")
    end

    it "normalizes inspected class objects" do
      expect(described_class.normalize("is expected to eq #<Class:User>"))
        .to eq("is expected to eq CLASS:User")
      expect(described_class.normalize("is expected to eq #<Class:0x000000010>"))
        .to eq("is expected to eq CLASS")
    end

    it "normalizes range values" do
      expect(described_class.normalize("is expected to eq 1..10"))
        .to eq("is expected to eq RANGE")
      expect(described_class.normalize("is expected to eq :a...:z"))
        .to eq("is expected to eq RANGE")
      expect(described_class.normalize("is expected to eq 2026-07-09..2026-07-10"))
        .to eq("is expected to eq RANGE")
    end

    it "normalizes array values" do
      expect(described_class.normalize("is expected to eq [1, 2, 3]"))
        .to eq("is expected to eq ARRAY")
      expect(described_class.normalize("is expected to eq []"))
        .to eq("is expected to eq ARRAY")
    end

    it "normalizes hash values" do
      expect(described_class.normalize("is expected to eq {:a=>1, :b=>2}"))
        .to eq("is expected to eq HASH")
      expect(described_class.normalize("is expected to eq {user_id: 1}"))
        .to eq("is expected to eq HASH")
    end

    it "does not normalize human labels that only look a little like Ruby literals" do
      expect(described_class.normalize("feature flag [beta] is enabled"))
        .to eq("feature flag [beta] is enabled")
      expect(described_class.normalize("renders {template}"))
        .to eq("renders {template}")
      expect(described_class.normalize("User logs in"))
        .to eq("User logs in")
    end
  end
end
