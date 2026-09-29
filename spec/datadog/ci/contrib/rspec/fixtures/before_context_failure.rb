RSpec.describe "Failing context setup" do
  before(:context) do
    raise "Context setup failed"
  end

  it "fails before its body runs" do
    raise "Example body must not run"
  end

  context "nested" do
    it "also fails before its body runs" do
      raise "Nested example body must not run"
    end
  end
end

RSpec.describe "Independent context" do
  it "still passes" do
    expect(1 + 1).to eq(2)
  end
end
