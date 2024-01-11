RSpec.shared_examples "Testing shared examples" do |expected_result|
  context "shared examples" do
    it "adds 1 and 1" do
      expect(1 + 1).to eq(expected_result)
    end
  end
end
