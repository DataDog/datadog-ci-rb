require "rspec"

RSpec.describe "SomeTest" do
  context "nested" do
    it "foo" do
      # DO NOTHING
    end

    it "fails" do
      expect(1).to eq(2)
    end

    it "is skipped", skip: true do
    end
  end
end
