# frozen_string_literal: true

RSpec.describe "RSpec test automation exclusions" do
  include_context "CI mode activated" do
    let(:integration_name) { :rspec }
    let(:flaky_test_retries_enabled) { true }
    let(:test_management_enabled) { true }
    let(:test_properties) { Hash.new({"quarantined" => true, "disabled" => true, "attempt_to_fix" => true}.freeze) }
  end

  before { test_tracing.start_test_session }

  it "runs an annotated disabled example once and preserves its blocking failure" do
    executions = []
    outcome = with_new_rspec_environment do
      RSpec.describe "protected examples" do
        it "fails", datadog_prevent_failure_suppression: true, datadog_no_auto_retry: true do
          executions << :executed
          raise "protected failure"
        end
      end.run
    end
    expect(outcome).to be(false)
    expect(executions).to eq([:executed])
    expect(first_test_span).to have_fail_status
    expect(first_test_span.get_tag("test.test_management.is_test_disabled")).to eq("true")
    expect(first_test_span.get_tag("test.test_management.prevent_failure_suppression")).to eq("true")
    expect(first_test_span.get_tag("test.test_management.no_auto_retry")).to eq("true")
    expect(first_test_span.get_tag("test.test_management.attempt_to_fix_passed")).to be_nil
  end

  it "does not reverse an explicit developer skip" do
    executions = []
    with_new_rspec_environment do
      RSpec.describe "protected examples" do
        it "is skipped", skip: true, datadog_prevent_failure_suppression: true, datadog_no_auto_retry: true do
          executions << :executed
        end
      end.run
    end
    expect(executions).to be_empty
    expect(first_test_span).to have_skip_status
    expect(first_test_span.get_tag("test.test_management.no_auto_retry")).to eq("true")
  end
end
