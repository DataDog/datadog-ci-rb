require_relative "helpers/helper"

max_flaky_test_failures = 4
flaky_test_executions = 0

def record_datadog_cucumber_execution(event)
  ::DatadogCucumberExecutionRecorder.record(event) if defined?(::DatadogCucumberExecutionRecorder)
end

Before do
  record_datadog_cucumber_execution(:before_hook)
  Datadog::CI.active_test.set_tag("cucumber_before_hook_executed", "true")
end

After do
  record_datadog_cucumber_execution(:after_hook)
  Datadog::CI.active_test.set_tag("cucumber_after_hook_executed", "true")
end

AfterStep do
  record_datadog_cucumber_execution(:after_step_hook)
  Datadog::CI.active_test.set_tag("cucumber_after_step_hook_executed", "true")
end

Then "datadog" do
  record_datadog_cucumber_execution(:datadog_step)
  Helper.help?
end

Then "failure" do
  record_datadog_cucumber_execution(:failure_step)
  expect(1 + 1).to eq(3)
end

Then "pending" do
  record_datadog_cucumber_execution(:pending_step)
  pending("implementation")
end

Then "skip" do
  record_datadog_cucumber_execution(:skip_step)
  skip_this_scenario
end

Then(/I add (-?\d+) and (-?\d+)/) do |n1, n2|
  record_datadog_cucumber_execution(:add_step)
  @res = n1.to_i + n2.to_i
end

Then(/the result should be (-?\d+)/) do |res|
  record_datadog_cucumber_execution(:result_step)
  expect(@res).to eq(res.to_i)
end

Then "flaky" do
  record_datadog_cucumber_execution(:flaky_step)
  if flaky_test_executions < max_flaky_test_failures
    flaky_test_executions += 1
    raise "Flaky test failure"
  else
    flaky_test_executions = 0
  end
end
