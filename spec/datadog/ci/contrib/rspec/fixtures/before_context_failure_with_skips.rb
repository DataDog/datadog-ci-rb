RSpec.describe "Context failure with managed examples" do
  before(:context) do
    raise "Context setup failed"
  end

  it("runnable") { raise "Example body must not run" }
  it("disabled") { raise "Example body must not run" }
  it("skippable") { raise "Example body must not run" }
  it("unskippable", datadog_itr_unskippable: true) { raise "Example body must not run" }
end
