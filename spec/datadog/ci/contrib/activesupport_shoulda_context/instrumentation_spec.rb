# frozen_string_literal: true

require "minitest"

RSpec.describe "ActiveSupport::TestCase instrumentation with shoulda context" do
  include_context "CI mode activated" do
    let(:integration_name) { :minitest }
    let(:integration_options) { {service_name: "ltest"} }
  end

  before do
    Minitest::Runnable.reset
    require_relative "test/entity_test"
    Minitest.run([])
  end

  it "instruments this minitest session" do
    # test session and module traced
    expect(test_session_span).not_to be_nil
    expect(test_module_span).not_to be_nil

    expect([test_session_span, test_module_span]).to all have_pass_status

    expect(test_suite_spans).to have(2).items
    expect(test_suite_spans).to have_tag_values_no_order(:status, ["pass", "pass"])
    expect(test_suite_spans).to have_tag_values_no_order(
      :suite,
      [
        "EntityTest at spec/datadog/ci/contrib/activesupport_shoulda_context/test/entity_test.rb",
        "attrs at spec/datadog/ci/contrib/activesupport_shoulda_context/test/test_attrs.rb"
      ]
    )

    # there is test span for every test case
    expect(test_spans).to have(8).items

    expect(test_spans).to have_tag_values_no_order(
      :name,
      [
        "test_: Entity should delegate #a to the #b object. ",
        "test_check_attr_at_/a",
        "test_check_attr_at_/b",
        "test_check_attr_at_/c",
        "test_check_attr_at_/d",
        "test_check_attr_at_/e",
        "test_check_attr_at_/g",
        "test_something"
      ]
    )
    # each test span has test suite, module, and session
    expect(test_spans).to all have_test_tag(:test_suite_id)
    expect(test_spans).to all have_test_tag(:test_module_id)
    expect(test_spans).to all have_test_tag(:test_session_id)
  end
end
