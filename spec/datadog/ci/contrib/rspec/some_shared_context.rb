RSpec.shared_context "Shared context" do
  let(:expected_result) { 42 }

  it "is 42" do
    expect(expected_result).to eq(42)
  end
end
