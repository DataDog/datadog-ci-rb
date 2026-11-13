# frozen_string_literal: true

require "minitest"

RSpec.describe "Session coverage when Minitest filters out every test" do
  include_context "CI mode activated"
  let(:integration_name) { :minitest }
  let(:itr_enabled) { true }
  let(:code_coverage_enabled) { true }

  around { |example| Thread.new { example.run }.value }

  it "does not report shared dependencies when the name filter matches no tests" do
    test_class = Class.new(Minitest::Test) do
      def test_example
        assert true
      end
    end
    stub_const("FilteredMinitestTest", test_class)
    allow(Minitest::Runnable).to receive(:runnables).and_return([test_class])

    Minitest.run(["--seed", "1", "--name", "test_removed"])
    Datadog::CI.active_test_session&.finish

    expect(test_spans).to be_empty
    expect(test_session_span).not_to be_nil
    expect(test_session_span).to have_test_tag(:code_coverage_enabled, "true")
    expect(session_coverage_events.size).to eq(0)
  end
end
