require "minitest"

RSpec.describe "Minitest instrumentation with thoughbot's shoulda-context gem for shared contexts" do
  include_context "CI mode activated" do
    let(:integration_name) { :minitest }
    let(:integration_options) { {service_name: "ltest"} }
    let(:itr_enabled) { true }
    let(:code_coverage_enabled) { true }
    let(:tests_skipping_enabled) { true }
  end

  let(:itr_skippable_tests) do
    Set.new([
      "CalculatorTest at spec/datadog/ci/contrib/minitest_shoulda_context/fake_test.rb.test_: a calculator should add two numbers for the sum. ."
    ])
  end

  before do
    Minitest::Runnable.reset

    require_relative "fake_test"

    Minitest.run([])
  end

  it "instruments this minitest session" do
    expect(test_session_span).not_to be_nil
    expect(test_module_span).not_to be_nil

    expect([test_session_span, test_module_span]).to all have_pass_status

    expect(test_suite_spans).to have(1).item
    expect(test_suite_spans).to have_tag_values_no_order(:status, ["pass"])

    expect(test_suite_spans).to have_tag_values_no_order(
      :suite,
      [
        "CalculatorTest at spec/datadog/ci/contrib/minitest_shoulda_context/fake_test.rb"
      ]
    )

    expect(test_spans).to have(3).items
    expect(test_spans).to have_tag_values_no_order(:status, ["pass", "pass", "skip"])

    expect(test_spans).to all have_test_tag(:test_suite_id)
    expect(test_spans).to have_unique_tag_values_count(:test_suite_id, 1)

    expect(test_spans).to have_tag_values_no_order(
      :name,
      [
        "test_: a calculator should add two numbers for the sum. ",
        "test_: a calculator should multiply two numbers for the product. ",
        "test_: a calculator should delegate #substract to the #substractor object. "
      ]
    )

    expect(test_spans).to all have_test_tag(:test_module_id)
    expect(test_spans).to all have_test_tag(:test_session_id)

    skipped_test = test_spans.find { |span| span.get_tag("test.status") == "skip" }
    expect(skipped_test).to have_test_tag(:itr_skipped_by_itr, "true")

    expect(test_session_span).to have_test_tag(:itr_tests_skipped, "true")
    expect(test_session_span).to have_test_tag(:itr_test_skipping_count, 1)
  end
end
