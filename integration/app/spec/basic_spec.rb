RSpec.describe "Let's do some math" do
  it "+" do
    expect(1 + 1).to eq(2)
  end

  it "**" do
    expect(3**3).to eq(27)
  end

  it "*" do
    expect(2 * 3).to eq(6)
  end

  it "/" do
    expect(3 / 2).to eq(1)
  end
end
