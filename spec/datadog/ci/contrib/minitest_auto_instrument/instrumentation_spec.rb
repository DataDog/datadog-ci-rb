RSpec.describe "Minitest auto instrumentation" do
  include_context "CI mode activated" do
    let(:integration_name) { :no_instrument }
  end
  include_context "Telemetry spy"

  before do
    require_relative "../../../../../lib/datadog/ci/auto_instrument"

    require "minitest"

    class SomeTest < Minitest::Test
      def test_pass
        assert true
      end

      def test_pass_other
        assert true
      end
    end

    Minitest.run([])
  end

  it "instruments test session" do
    expect(test_session_span).not_to be_nil
    expect(test_module_span).not_to be_nil

    expect(first_test_suite_span).not_to be_nil
    expect(first_test_suite_span.name).to eq(
      "SomeTest at spec/datadog/ci/contrib/minitest_auto_instrument/instrumentation_spec.rb"
    )

    expect(test_spans).to have(2).items
    expect(test_spans).to have_unique_tag_values_count(:test_session_id, 1)
    expect(test_spans).to have_unique_tag_values_count(:test_module_id, 1)
    expect(test_spans).to have_unique_tag_values_count(:test_suite_id, 1)

    # test_session metric has auto_injected tag
    test_session_started_metric = telemetry_metric(:inc, "test_session")
    expect(test_session_started_metric.tags["auto_injected"]).to eq("true")
  end
end
