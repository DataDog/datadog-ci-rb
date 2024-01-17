RSpec.describe Datadog::CI::NullSpan do
  subject(:span) { described_class.new }

  describe "#name" do
    it "returns nil" do
      expect(span.name).to be_nil
    end
  end

  describe "#passed!" do
    it "returns nil" do
      expect(span.passed!).to be_nil
    end
  end

  describe "#failed!" do
    it "returns nil" do
      expect(span.failed!).to be_nil
    end
  end

  describe "#skipped!" do
    it "returns nil" do
      expect(span.skipped!).to be_nil
    end
  end

  describe "#set_tag" do
    it "returns nil" do
      expect(span.set_tag("foo", "bar")).to be_nil
    end
  end

  describe "#set_tags" do
    it "returns nil" do
      expect(span.set_tags("foo" => "bar", "baz" => "qux")).to be_nil
    end
  end

  describe "#set_metric" do
    it "returns nil" do
      expect(span.set_metric("foo", "bar")).to be_nil
    end
  end

  describe "#set_default_tags" do
    it "returns nil" do
      expect(span.set_default_tags).to be_nil
    end
  end

  describe "#set_environment_runtime_tags" do
    it "returns nil" do
      expect(span.set_environment_runtime_tags).to be_nil
    end
  end

  describe "#finish" do
    it "returns nil" do
      expect(span.finish).to be_nil
    end
  end

  describe "#type" do
    it "returns nil" do
      expect(span.type).to be_nil
    end
  end
end
