# this file is required for knapsack unit tests

Datadog.configure do |c|
  c.service = "knapsack_rspec_example"
  c.ci.enabled = true
  c.ci.git_metadata_upload_enabled = false
  c.ci.instrument :rspec
end
