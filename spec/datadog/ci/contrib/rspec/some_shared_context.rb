RSpec.shared_context "Shared context" do
  let(:expected_result) { 42 }

  it "is 42" do
    expect(42).to eq(expected_result)
  end
end
