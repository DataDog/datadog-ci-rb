Then "datadog" do
  true
end

Then "failure" do
  expect(1 + 1).to eq(3)
end
