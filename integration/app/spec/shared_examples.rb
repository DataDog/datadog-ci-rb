RSpec.shared_examples "Testing shared examples" do
  context "shared examples" do
    it "adds 1 and 1" do
      expect(1 + 1).to eq(2)
    end
  end
end
