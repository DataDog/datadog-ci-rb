require "minitest"

RSpec.describe "Minitest instrumentation with thoughbot's shoulda-context and unskippable tests" do
  include_context "CI mode activated" do
    let(:integration_name) { :minitest }
    let(:integration_options) { {service_name: "ltest"} }
    let(:itr_enabled) { true }
    let(:code_coverage_enabled) { true }
    let(:tests_skipping_enabled) { true }
  end

  let(:itr_skippable_tests) do
    Set.new([
      "CalculatorUnskippableTest at spec/datadog/ci/contrib/minitest_shoulda_context/fake_unskippable_test.rb.test_: a calculator should add two numbers for the sum. ."
    ])
  end

  before do
    Minitest::Runnable.reset

    require_relative "fake_unskippable_test"

    Minitest.run([])
  end

  it "instruments this minitest session and doesn't skip tests" do
    expect(test_spans).to have(3).items
    expect(test_spans).to all have_pass_status

    forced_run_test = test_spans.find { |span| span.get_tag("test.itr.forced_run") == "true" }
    expect(forced_run_test).not_to be_nil

    expect(test_session_span).to have_test_tag(:itr_tests_skipped, "false")
    expect(test_session_span).to have_test_tag(:itr_test_skipping_count, 0)
  end
end
