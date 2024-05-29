require "minitest"

RSpec.describe "Minitest instrumentation" do
  include_context "CI mode activated" do
    let(:integration_name) { :minitest }
    let(:integration_options) { {service_name: "ltest"} }

    let(:itr_enabled) { true }
    let(:code_coverage_enabled) { true }
    let(:tests_skipping_enabled) { true }
  end
  let(:time_1990) { Time.utc(1990) }

  before do
    # required to call .runnable_methods
    Minitest.seed = 1
    Minitest::Runnable.reset

    Timecop.freeze(time_1990)

    class SomeTest < Minitest::Test
      def test_pass
        assert true
      end
    end

    Minitest.run([])
  end

  it "does not set frozen time when setting start time for traces" do
    expect(first_test_span.start_time).not_to eq(time_1990)
    expect(test_session_span.start_time).not_to eq(time_1990)
  end
end
