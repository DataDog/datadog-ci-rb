# frozen_string_literal: true

require "minitest"

RSpec.describe "Minitest executor adversarial concurrency" do
  include_context "CI mode activated" do
    let(:integration_name) { :minitest }
    let(:itr_enabled) { true }
    let(:code_coverage_enabled) { true }
    let(:tests_skipping_enabled) { true }
    let(:flaky_test_retries_enabled) { true }
    let(:itr_skippable_tests) do
      Set.new(["AdversarialSequentialTest at spec/datadog/ci/contrib/minitest/concurrency_spec.rb.test_first."])
    end
  end

  it "rejects a mixed runner before skipping or retrying any tests" do
    expect_in_fork do
      Minitest::Runnable.reset
      calls = Queue.new
      sequential = Class.new(Minitest::Test) do
        define_method(:test_first) do
          calls << name
          assert_nil Datadog::CI.active_test
        end
      end
      threaded = Class.new(Minitest::Test) do
        parallelize_me!
        define_method(:test_failure) do
          calls << name
          assert_nil Datadog::CI.active_test
          flunk "customer failure"
        end
      end
      stub_const("AdversarialSequentialTest", sequential)
      stub_const("AdversarialThreadedTest", threaded)
      expect(Datadog.logger).to receive(:warn).with(/Minitest threaded executor is unsupported/).once

      expect(Minitest.run([])).to be(false)
      expect(calls.size).to eq(2)
      expect(Array.new(2) { calls.pop }).to contain_exactly("test_first", "test_failure")
      expect(test_spans).to be_empty
      expect(coverage_events).to be_empty
      expect(test_tracing).not_to be_execution_supported
    end
  end

  it "runs overlapping customer tests safely when an executor bypasses preflight" do
    expect_in_fork do
      Minitest.seed = 1
      test_tracing.start_test_session
      test_tracing.start_test_module("minitest")
      first_running, second_running = Queue.new, Queue.new
      calls, results = Queue.new, Queue.new
      impact = Datadog.send(:components).test_impact_analysis
      expect(impact).not_to receive(:write)
      expect(Datadog.logger).to receive(:warn).with(/Minitest threaded executor is unsupported/).once

      klass = Class.new(Minitest::Test) do
        parallelize_me!
        define_method(:test_first) do
          first_running << true
          second_running.pop
          calls << name
          assert_nil Datadog::CI.active_test
        end
        define_method(:test_second) do
          first_running.pop
          second_running << true
          calls << name
          assert_nil Datadog::CI.active_test
        end
      end
      stub_const("AdversarialThreadedTest", klass)
      reporter = Minitest::AbstractReporter.new
      allow(reporter).to receive(:record) { |result| results << result }
      executor = Minitest::Parallel::Executor.new(2)
      executor.start
      executor << [klass, "test_first", reporter]
      executor << [klass, "test_second", reporter]
      executor.shutdown

      expect(results.size).to eq(2)
      expect(Array.new(2) { results.pop }.map(&:passed?)).to eq([true, true])
      expect(calls.size).to eq(2)
      expect(test_spans).to be_empty
      expect(test_tracing).not_to be_execution_supported
    end
  end
end
