RSpec.describe "Let's do some math" do
  it "add" do
    expect(1 + 1).to eq(2)
  end

  it "pow" do
    expect(3**3).to eq(27)
  end

  it "mul" do
    expect(2 * 3).to eq(6)
  end

  it "div" do
    expect(3 / 2).to eq(1)
  end
end
