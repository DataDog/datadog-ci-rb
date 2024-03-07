require "minitest"

RSpec.describe "Minitest instrumentation with thoughbot's shoulda-context gem for shared contexts" do
  include_context "CI mode activated" do
    let(:integration_name) { :minitest }
    let(:integration_options) { {service_name: "ltest"} }
  end

  before do
    Minitest::Runnable.reset

    require_relative "fake_test"

    Minitest.run([])
  end

  it "instruments this minitest session" do
    # test session and module traced
    expect(test_session_span).not_to be_nil
    expect(test_module_span).not_to be_nil

    # test session and module are failed
    expect([test_session_span, test_module_span]).to all have_pass_status

    # test suite spans are created for each test as for parallel execution
    expect(test_suite_spans).to have(1).item
    expect(test_suite_spans).to have_tag_values_no_order(:status, ["pass"])

    expect(test_suite_spans).to have_tag_values_no_order(
      :suite,
      [
        "CalculatorTest at spec/datadog/ci/contrib/minitest_shoulda_context/fake_test.rb"
      ]
    )

    # there is test span for every test case
    expect(test_spans).to have(3).items

    expect(test_spans).to all have_test_tag(:test_suite_id)
    expect(test_spans).to have_unique_tag_values_count(:test_suite_id, 1)

    # every test span is connected to test module and test session
    expect(test_spans).to all have_test_tag(:test_module_id)
    expect(test_spans).to all have_test_tag(:test_session_id)
  end
end
