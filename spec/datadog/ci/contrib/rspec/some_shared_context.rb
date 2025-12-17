require_relative "some_constants"

RSpec.shared_context "Shared context" do
  let(:expected_result) { 42 }

  it "is 42" do
    expect(Constants::MY_CONSTANT).to eq(expected_result)
  end
end
