require "minitest"

RSpec.describe "Minitest instrumentation with maxitest around hooks" do
  include_context "CI mode activated" do
    let(:integration_name) { :minitest }
    let(:integration_options) { {service_name: "ltest"} }
  end

  before do
    Minitest::Runnable.reset

    require "minitest/spec"
    require "maxitest/vendor/around"
    require_relative "fake_test"
  end

  it "instruments this minitest session" do
    expect(Minitest.run([])).to be(true)

    expect(test_session_span).not_to be_nil
    expect(test_module_span).not_to be_nil

    expect([test_session_span, test_module_span]).to all have_pass_status

    expect(test_suite_spans).to have(1).item
    expect(test_suite_spans.first).to have_pass_status

    expect(test_spans).to have(2).items
    expect(test_spans).to all have_pass_status
    expect(test_spans).to all have_test_tag(:test_suite_id)
    expect(test_spans).to all have_test_tag(:test_module_id)
    expect(test_spans).to all have_test_tag(:test_session_id)
  end
end
