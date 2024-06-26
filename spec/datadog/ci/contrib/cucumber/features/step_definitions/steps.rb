require_relative "helpers/helper"

Then "datadog" do
  Helper.help?
end

Then "failure" do
  expect(1 + 1).to eq(3)
end

Then "pending" do
  pending("implementation")
end

Then "skip" do
  skip_this_scenario
end

Then(/I add (-?\d+) and (-?\d+)/) do |n1, n2|
  @res = n1.to_i + n2.to_i
end

Then(/the result should be (-?\d+)/) do |res|
  expect(@res).to eq(res.to_i)
end
