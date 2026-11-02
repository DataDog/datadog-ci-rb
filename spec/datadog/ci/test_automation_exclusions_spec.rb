# frozen_string_literal: true

RSpec.describe "Test automation exclusion policy" do
  include_context "CI mode activated" do
    let(:flaky_test_retries_enabled) { true }
    let(:early_flake_detection_enabled) { true }
    let(:known_tests) { Set.new(["existing-test"]) }
    let(:test_management_enabled) { true }
    let(:test_properties) { Hash.new(properties) }
  end

  let(:properties) { {"quarantined" => true, "disabled" => true, "attempt_to_fix" => true} }

  before do
    test_tracing.start_test_session
    test_tracing.start_test_module("manual")
    test_tracing.start_test_suite("suite")
  end

  def run_test(prevent_failure_suppression: false, no_auto_retry: false)
    attempts = 0
    Datadog.send(:components).test_retries.with_retries do
      test_tracing.trace_test("test", "suite", prevent_failure_suppression: prevent_failure_suppression, no_auto_retry: no_auto_retry) do |test|
        attempts += 1
        test.should_skip? ? test.skipped!(reason: test.datadog_skip_reason) : test.failed!(exception: RuntimeError.new("failure"))
      end
    end
    attempts
  end

  it "retains all assignments while both exclusions run one blocking failure" do
    expect(run_test(prevent_failure_suppression: true, no_auto_retry: true)).to eq(1)
    expect(first_test_span).to have_fail_status
    %w[is_quarantined is_test_disabled is_attempt_to_fix prevent_failure_suppression no_auto_retry].each do |tag|
      expect(first_test_span.get_tag("test.test_management.#{tag}")).to eq("true")
    end
    expect(first_test_span.get_tag("test.test_management.attempt_to_fix_passed")).to be_nil
    expect(first_test_span.get_tag("test.retry_reason")).to be_nil
    expect(first_test_span.get_tag("test.final_status")).to eq("fail")
  end

  it "reapplies disable after automatic attempt-to-fix is excluded" do
    expect(run_test(no_auto_retry: true)).to eq(1)
    expect(first_test_span).to have_skip_status
    expect(first_test_span.get_tag("test.test_management.no_auto_retry")).to eq("true")
    expect(first_test_span.get_tag("test.test_management.attempt_to_fix_passed")).to be_nil
  end

  context "with quarantine and attempt-to-fix assignments" do
    let(:properties) { {"quarantined" => true, "attempt_to_fix" => true} }

    it "retains quarantine after automatic attempt-to-fix is excluded" do
      expect(run_test(no_auto_retry: true)).to eq(1)
      expect(first_test_span).to have_fail_status
      expect(first_test_span.get_tag("test.final_status")).to eq("pass")
    end
  end

  context "without management assignments" do
    let(:properties) { {} }

    it "excludes both ATR and EFD without excluding test discovery" do
      expect(run_test(no_auto_retry: true)).to eq(1)
      expect(first_test_span.get_tag("test.is_new")).to eq("true")
      expect(first_test_span.get_tag("test.is_retry")).to be_nil
    end

    it "does not prevent automatic retries with only failure suppression excluded" do
      expect(run_test(prevent_failure_suppression: true)).to be > 1
      expect(test_spans).to all(satisfy { |span| span.get_tag("test.test_management.prevent_failure_suppression") == "true" })
      expect(test_spans).to all(satisfy { |span| span.get_tag("test.test_management.no_auto_retry").nil? })
    end

    it "preserves externally scheduled retries and their classification" do
      Datadog.send(:components).test_retries.with_retries do
        test_tracing.trace_test("test", "suite", no_auto_retry: true) { |test| test.failed!(exception: RuntimeError.new("first attempt")) }
        test_tracing.trace_test("test", "suite", no_auto_retry: true) { |test| test.passed! }
      end
      expect(test_spans.size).to eq(2)
      expect(test_spans).to all(satisfy { |span| span.get_tag("test.test_management.no_auto_retry") == "true" })
      retried = test_spans.find { |span| span.get_tag("test.is_retry") == "true" }
      expect(retried.get_tag("test.retry_reason")).to eq("external")
      expect(retried.get_tag("test.test_management.attempt_to_fix_passed")).to be_nil
    end

    it "does not interpret manually set span tags as declarations" do
      test_tracing.trace_test("test", "suite") do |test|
        test.set_tag("test.test_management.no_auto_retry", "true")
        test.set_tag("test.test_management.prevent_failure_suppression", "true")
        expect(test.no_auto_retry?).to be(false)
        expect(test.prevent_failure_suppression?).to be(false)
        test.passed!
      end
    end

    it "does not retain exclusions in a later execution" do
      test_tracing.trace_test("test", "suite", no_auto_retry: true) { |test| test.passed! }
      test_tracing.trace_test("test", "suite") do |test|
        expect(test.no_auto_retry?).to be(false)
        expect(test.get_tag("test.test_management.no_auto_retry")).to be_nil
        test.passed!
      end
    end
  end
  context "when Test Impact Analysis selects the test for skipping" do
    let(:itr_enabled) { true }
    let(:tests_skipping_enabled) { true }
    let(:itr_skippable_tests) { [Datadog::CI::Utils::TestRun.datadog_test_id("test", "suite")] }

    it "retains TIA skipping even with both exclusions" do
      expect(run_test(prevent_failure_suppression: true, no_auto_retry: true)).to eq(1)
      expect(first_test_span).to have_skip_status
      expect(first_test_span.get_tag("test.skipped_by_itr")).to eq("true")
      expect(first_test_span.get_tag("test.test_management.prevent_failure_suppression")).to eq("true")
    end
  end
end
