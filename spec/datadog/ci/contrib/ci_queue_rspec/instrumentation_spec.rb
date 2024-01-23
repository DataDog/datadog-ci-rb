require "fileutils"

RSpec.describe "RSpec instrumentation with Shopify's ci-queue runner" do
  include_context "CI mode activated" do
    let(:integration_name) { :rspec }
  end

  let(:run_id) { rand(1..2**64 - 1) }

  before do
    FileUtils.mkdir("log")
  end

  after do
    FileUtils.rm_rf("log")
  end

  it "instruments this rspec session" do
    expect(1 + 1).to eq(2)
  end
end
