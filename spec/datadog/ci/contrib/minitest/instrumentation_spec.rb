require "time"

require "minitest"
require "minitest/spec"

# minitest adds `describe` method to Kernel, which conflicts with RSpec.
# here we define `minitest_describe` method to avoid this conflict.
module Kernel
  alias_method :minitest_describe, :describe
end

RSpec.describe "Minitest instrumentation" do
  let(:integration) { Datadog::CI::Contrib::Instrumentation.fetch_integration(:minitest) }

  before do
    # expect that public manual API isn't used
    expect(Datadog::CI).to receive(:start_test_session).never
    expect(Datadog::CI).to receive(:start_test_module).never
    expect(Datadog::CI).to receive(:start_test_suite).never
    expect(Datadog::CI).to receive(:start_test).never
  end

  context "without service name configured" do
    include_context "CI mode activated" do
      let(:integration_name) { :minitest }
    end

    it "uses repo name as default service name" do
      klass = Class.new(Minitest::Test) do
        def test_foo
        end
      end

      klass.new(:test_foo).run

      expect(span.service).to eq("datadog-ci-rb")
    end
  end

  context "with service name configured and code coverage enabled" do
    include_context "CI mode activated" do
      let(:service_name) { "ltest" }
      let(:integration_name) { :minitest }
      let(:integration_options) { {service_name: "ltest"} }

      let(:itr_enabled) { true }
      let(:code_coverage_enabled) { true }
      let(:tests_skipping_enabled) { true }
    end

    before do
      # required to call .runnable_methods
      Minitest.seed = 1
    end

    it "creates span for test" do
      klass = Class.new(Minitest::Test) do
        def self.name
          "SomeTest"
        end

        def test_foo
        end
      end

      klass.new(:test_foo).run

      expect(span.type).to eq(Datadog::CI::Ext::AppTypes::TYPE_TEST)
      expect(span.name).to eq("test_foo")
      expect(span.resource).to eq("test_foo")
      expect(span.service).to eq("ltest")

      expect(span).to have_test_tag(:name, "test_foo")
      expect(span).to have_test_tag(
        :suite,
        "SomeTest at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb"
      )
      expect(span).to have_test_tag(:span_kind, "test")
      expect(span).to have_test_tag(:type, "test")
      expect(span).to have_test_tag(:framework, "minitest")
      expect(span).to have_test_tag(
        :framework_version,
        integration.version.to_s
      )

      expect(span).to have_pass_status

      expect(span).to have_test_tag(
        :source_file,
        "spec/datadog/ci/contrib/minitest/instrumentation_spec.rb"
      )
      expect(span).to have_test_tag(:source_start, "62")
      expect(span).to have_test_tag(:source_end, "63") unless PlatformHelpers.jruby?

      expect(span).to have_test_tag(
        :codeowners,
        "[\"@DataDog/ruby-guild\", \"@DataDog/ci-app-libraries\"]"
      )
    end

    it "creates spans for several tests" do
      expect(Datadog::CI::Ext::Environment).to receive(:tags).once.and_call_original

      num_tests = 20

      klass = Class.new(Minitest::Test) do
        def self.name
          "SomeTest"
        end

        num_tests.times do |i|
          define_method(:"test_#{i}") {}
        end
      end

      num_tests.times do |i|
        klass.new("test_#{i}").run
      end

      expect(spans).to have(num_tests).items
    end

    it "creates span for spec" do
      klass = Class.new(Minitest::Spec) do
        def self.name
          "SomeSpec"
        end

        it "does not fail" do
        end
      end

      method_name = klass.runnable_methods.first
      klass.new(method_name).run

      expect(span.type).to eq(Datadog::CI::Ext::AppTypes::TYPE_TEST)
      expect(span.resource).to eq(method_name)
      expect(span.service).to eq("ltest")
      expect(span).to have_test_tag(:name, method_name)
      expect(span).to have_test_tag(
        :suite,
        "SomeSpec at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb"
      )
    end

    it "creates spans for several specs" do
      num_specs = 20

      klass = Class.new(Minitest::Spec) do
        def self.name
          "SomeSpec"
        end

        num_specs.times do |i|
          it "does not fail #{i}" do
          end
        end
      end

      klass.runnable_methods.each do |method_name|
        klass.new(method_name).run
      end

      expect(spans).to have(num_specs).items
    end

    it "creates spans for example with instrumentation" do
      klass = Class.new(Minitest::Test) do
        def self.name
          "SomeTest"
        end

        def test_foo
          Datadog::Tracing.trace("get_time") do
            Time.now
          end
        end
      end

      klass.new(:test_foo).run

      expect(spans).to have(2).items
      expect(spans).to all have_origin(Datadog::CI::Ext::Test::CONTEXT_ORIGIN)
    end

    context "catches failures" do
      def expect_failure
        expect(span).to have_fail_status
        expect(span).to have_error
        expect(span).to have_error_type
        expect(span).to have_error_message
        expect(span).to have_error_stack
      end

      it "within test" do
        klass = Class.new(Minitest::Test) do
          def self.name
            "SomeTest"
          end

          def test_foo
            assert false
          end
        end

        klass.new(:test_foo).run

        expect_failure
      end

      it "within setup" do
        klass = Class.new(Minitest::Test) do
          def self.name
            "SomeTest"
          end

          def setup
            assert false
          end

          def test_foo
          end
        end

        klass.new(:test_foo).run

        expect_failure
      end

      it "within teardown" do
        klass = Class.new(Minitest::Test) do
          def self.name
            "SomeTest"
          end

          def teardown
            assert false
          end

          def test_foo
          end
        end

        klass.new(:test_foo).run

        expect_failure
      end
    end

    context "catches errors" do
      def expect_failure
        expect(span).to have_fail_status
        expect(span).to have_error
        expect(span).to have_error_type
        expect(span).to have_error_message
        expect(span).to have_error_stack
      end

      it "within test" do
        klass = Class.new(Minitest::Test) do
          def self.name
            "SomeTest"
          end

          def test_foo
            raise "Error!"
          end
        end

        klass.new(:test_foo).run

        expect_failure
      end

      it "within setup" do
        klass = Class.new(Minitest::Test) do
          def self.name
            "SomeTest"
          end

          def setup
            raise "Error!"
          end

          def test_foo
          end
        end

        klass.new(:test_foo).run

        expect_failure
      end

      it "within teardown" do
        klass = Class.new(Minitest::Test) do
          def self.name
            "SomeTest"
          end

          def teardown
            raise "Error!"
          end

          def test_foo
          end
        end

        klass.new(:test_foo).run

        expect_failure
      end
    end

    context "catches skips" do
      def expect_skip
        expect(span).to have_skip_status
        expect(span).to_not have_error
      end

      it "with reason" do
        klass = Class.new(Minitest::Test) do
          def self.name
            "SomeTest"
          end

          def test_foo
            skip "Skip!"
          end
        end

        klass.new(:test_foo).run

        expect_skip
        expect(span).to have_test_tag(:skip_reason, "Skip!")
      end

      it "without reason" do
        klass = Class.new(Minitest::Test) do
          def self.name
            "SomeTest"
          end

          def test_foo
            skip
          end
        end

        klass.new(:test_foo).run

        expect_skip
        expect(span).to have_test_tag(:skip_reason, "Skipped, no message given")
      end

      it "within test" do
        klass = Class.new(Minitest::Test) do
          def self.name
            "SomeTest"
          end

          def test_foo
            skip "Skip!"
          end
        end

        klass.new(:test_foo).run

        expect_skip
      end

      it "within setup" do
        klass = Class.new(Minitest::Test) do
          def self.name
            "SomeTest"
          end

          def setup
            skip "Skip!"
          end

          def test_foo
          end
        end

        klass.new(:test_foo).run

        expect_skip
      end

      it "within teardown" do
        klass = Class.new(Minitest::Test) do
          def self.name
            "SomeTest"
          end

          def teardown
            skip "Skip!"
          end

          def test_foo
          end
        end

        klass.new(:test_foo).run

        expect_skip
      end
    end

    context "run minitest suite" do
      include_context "Telemetry spy"

      before do
        Minitest.run([])
      end

      context "passed tests" do
        before(:context) do
          Minitest::Runnable.reset

          require_relative "helpers/addition_helper"
          require_relative "helpers/simple_model"
          class SomeTest < Minitest::Test
            def test_pass
              assert true
            end

            def test_pass_other
              # make sure that allocating objects is covered
              SimpleModel.new
              # add thread to test that code coverage is collected
              t = Thread.new do
                AdditionHelper.add(1, 2)
              end
              t.join
              assert true
            end
          end
        end

        it "creates a test session span" do
          expect(test_session_span).not_to be_nil
          expect(test_session_span.type).to eq("test_session_end")
          expect(test_session_span).to have_test_tag(:span_kind, "test")
          expect(test_session_span).to have_test_tag(:framework, "minitest")
          expect(test_session_span).to have_test_tag(
            :framework_version,
            integration.version.to_s
          )

          # ITR
          expect(test_session_span).to have_test_tag(:itr_test_skipping_enabled, "true")
          expect(test_session_span).to have_test_tag(:itr_test_skipping_type, "test")
          expect(test_session_span).to have_test_tag(:itr_tests_skipped, "false")
          expect(test_session_span).to have_test_tag(:itr_test_skipping_count, 0)

          # Total code coverage
          expect(test_session_span).to have_test_tag(:code_coverage_lines_pct)

          expect(test_session_span).to have_pass_status

          # test_session telemetry metric has auto_injected false
          test_session_started_metric = telemetry_metric(:inc, "test_session")
          expect(test_session_started_metric.tags["auto_injected"]).to eq("false")
        end

        it "creates a test module span" do
          expect(test_module_span).not_to be_nil

          expect(test_module_span.type).to eq("test_module_end")
          expect(test_module_span.name).to eq("minitest")

          expect(test_module_span).to have_test_tag(:span_kind, "test")
          expect(test_module_span).to have_test_tag(:framework, "minitest")
          expect(test_module_span).to have_test_tag(
            :framework_version,
            integration.version.to_s
          )
          expect(test_module_span).to have_pass_status
        end

        it "creates a test suite span" do
          expect(first_test_suite_span).not_to be_nil

          expect(first_test_suite_span.type).to eq("test_suite_end")
          expect(first_test_suite_span.name).to eq("SomeTest at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb")

          expect(first_test_suite_span).to have_test_tag(:span_kind, "test")
          expect(first_test_suite_span).to have_test_tag(:framework, "minitest")
          expect(first_test_suite_span).to have_test_tag(
            :framework_version,
            integration.version.to_s
          )

          expect(first_test_suite_span).to have_test_tag(
            :source_file,
            "spec/datadog/ci/contrib/minitest/instrumentation_spec.rb"
          )
          expect(first_test_suite_span).to have_test_tag(:source_start, "422")
          expect(first_test_suite_span).to have_test_tag(
            :codeowners,
            "[\"@DataDog/ruby-guild\", \"@DataDog/ci-app-libraries\"]"
          )

          expect(first_test_suite_span).to have_pass_status
        end

        it "creates test spans and connects them to the session, module, and suite" do
          expect(test_spans).to have(2).items

          expect(test_spans).to have_unique_tag_values_count(:test_session_id, 1)
          expect(test_spans).to have_unique_tag_values_count(:test_module_id, 1)
          expect(test_spans).to have_unique_tag_values_count(:test_suite_id, 1)

          expect(first_test_span).to have_test_tag(
            :suite,
            "SomeTest at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb"
          )
          expect(first_test_span).to have_test_tag(:framework, "minitest")
          expect(first_test_span).to have_test_tag(
            :framework_version,
            integration.version.to_s
          )
          expect(first_test_span).to have_pass_status

          expect(first_test_span).to have_test_tag(:test_session_id, test_session_span.id.to_s)
          expect(first_test_span).to have_test_tag(:test_module_id, test_module_span.id.to_s)
          expect(first_test_span).to have_test_tag(:test_suite_id, first_test_suite_span.id.to_s)
        end

        it "creates code coverage events" do
          skip if PlatformHelpers.jruby?

          expect(coverage_events).to have(2).items

          expect_coverage_events_belong_to_session(test_session_span)
          expect_coverage_events_belong_to_suite(first_test_suite_span)
          expect_coverage_events_belong_to_tests(test_spans)
          expect_non_empty_coverages

          # expect that background thread is covered
          test_span = test_spans.find { |span| span.get_tag("test.name") == "test_pass_other" }
          cov_event = find_coverage_for_test(test_span)
          expect(cov_event.coverage.keys).to include(absolute_path("helpers/addition_helper.rb"))
          expect(cov_event.coverage.keys).to include(absolute_path("helpers/simple_model.rb"))
        end

        context "when test optimisation skips tests" do
          context "single skipped test" do
            let(:itr_skippable_tests) do
              Set.new(["SomeTest at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb.test_pass."])
            end

            it "skips a single test" do
              expect(test_spans).to have(2).items
              expect(test_spans).to have_tag_values_no_order(:status, ["skip", "pass"])

              expect(first_test_span).to have_test_tag(:itr_skipped_by_itr, "true")
              expect(test_spans.last).not_to have_test_tag(:itr_skipped_by_itr)
            end

            it "send test session level tags" do
              expect(test_session_span).to have_test_tag(:itr_test_skipping_enabled, "true")
              expect(test_session_span).to have_test_tag(:itr_test_skipping_type, "test")
              expect(test_session_span).to have_test_tag(:itr_tests_skipped, "true")
              expect(test_session_span).to have_test_tag(:itr_test_skipping_count, 1)
            end
          end

          context "multiple skipped tests" do
            let(:itr_skippable_tests) do
              Set.new(
                [
                  "SomeTest at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb.test_pass.",
                  "SomeTest at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb.test_pass_other."
                ]
              )
            end

            it "skips all tests" do
              expect(test_spans).to have(2).items
              expect(test_spans).to all have_skip_status

              expect(test_spans).to all have_test_tag(:itr_skipped_by_itr, "true")
            end

            it "send test session level tags" do
              expect(test_session_span).to have_test_tag(:itr_test_skipping_enabled, "true")
              expect(test_session_span).to have_test_tag(:itr_test_skipping_type, "test")
              expect(test_session_span).to have_test_tag(:itr_tests_skipped, "true")
              expect(test_session_span).to have_test_tag(:itr_test_skipping_count, 2)
            end
          end
        end
      end

      context "single test failed" do
        before(:context) do
          Minitest::Runnable.reset

          class SomeFailedTest < Minitest::Test
            def test_fail
              assert false
            end
          end
        end

        it "traces test, test session, test module with failed status" do
          expect(first_test_span).to have_test_tag(:name, "test_fail")

          expect(
            [first_test_span, first_test_suite_span, test_session_span, test_module_span]
          ).to all have_fail_status
        end
      end

      context "using Minitest::Spec" do
        before(:context) do
          Minitest::Runnable.reset

          class SomeSpec < Minitest::Spec
            it "does not fail" do
            end

            minitest_describe "in context" do
              it "does not fail" do
              end

              minitest_describe "deeper context" do
                it "does not fail" do
                end
              end
            end

            minitest_describe "in other context" do
              it "does not fail" do
              end
            end
          end
        end

        it "traces tests with unique names" do
          expect(test_spans).to have_tag_values_no_order(
            :name,
            [
              "test_0001_does not fail",
              "test_0001_does not fail",
              "test_0001_does not fail",
              "test_0001_does not fail"
            ]
          )
        end

        it "connects tests to different test suites (one per spec context)" do
          expect(test_spans).to have_unique_tag_values_count(:test_suite_id, 4)
          expect(test_spans).to have_tag_values_no_order(
            :suite,
            [
              "SomeSpec at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb",
              "SomeSpec::in context at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb",
              "SomeSpec::in context::deeper context at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb",
              "SomeSpec::in other context at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb"
            ]
          )
        end

        it "connects tests to a single test session" do
          expect(test_spans).to have_unique_tag_values_count(:test_session_id, 1)
          expect(first_test_span).to have_test_tag(:test_session_id, test_session_span.id.to_s)
        end
      end

      context "using parallel executor" do
        before(:context) do
          Minitest::Runnable.reset

          class ParallelTest < Minitest::Test
            parallelize_me!
          end

          class TestA < ParallelTest
            def test_a_1
              Datadog::CI.active_test.set_tag("minitest_thread", Thread.current.object_id)
              sleep 0.1
            end

            def test_a_2
              Datadog::CI.active_test.set_tag("minitest_thread", Thread.current.object_id)
              sleep 0.1
            end
          end

          class TestB < ParallelTest
            def test_b_1
              Datadog::CI.active_test.set_tag("minitest_thread", Thread.current.object_id)
              sleep 0.1
            end

            def test_b_2
              Datadog::CI.active_test.set_tag("minitest_thread", Thread.current.object_id)
              sleep 0.1
            end
          end
        end

        it "traces all tests and test suites correctly" do
          test_threads = test_spans.map { |span| span.get_tag("minitest_thread") }.uniq

          # make sure that tests were executed concurrently
          # note that this test could be flaky
          expect(test_threads.count).to be > 1

          expect(test_spans).to have_tag_values_no_order(
            :name,
            [
              "test_a_1",
              "test_a_2",
              "test_b_1",
              "test_b_2"
            ]
          )
          expect(test_spans).to have_unique_tag_values_count(:test_suite_id, 2)
        end

        it "connects tests to a single test session and a single test module" do
          expect(test_spans).to have_unique_tag_values_count(:test_module_id, 1)
          expect(test_spans).to have_unique_tag_values_count(:test_session_id, 1)

          expect(first_test_span).to have_test_tag(:test_module_id, test_module_span.id.to_s)
          expect(first_test_span).to have_test_tag(:test_session_id, test_session_span.id.to_s)
        end

        it "creates test suite spans" do
          expect(test_suite_spans).to have(2).items

          expect(test_suite_spans).to have_tag_values_no_order(
            :suite,
            [
              "TestA at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb",
              "TestB at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb"
            ]
          )
        end

        it "creates code coverage events" do
          skip if PlatformHelpers.jruby?

          expect(coverage_events).to have(4).items

          expect_coverage_events_belong_to_session(test_session_span)
          expect_coverage_events_belong_to_suites(test_suite_spans)
          expect_coverage_events_belong_to_tests(test_spans)
          expect_non_empty_coverages
        end

        context "when test optimisation skips tests" do
          let(:itr_skippable_tests) do
            Set.new(
              [
                "TestA at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb.test_a_1.",
                "TestA at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb.test_a_2.",
                "TestB at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb.test_b_2."
              ]
            )
          end

          it "skips given tests" do
            expect(test_spans).to have(4).items
            expect(test_spans).to have_tag_values_no_order(:status, ["skip", "skip", "skip", "pass"])

            skipped = test_spans.select { |span| span.get_tag("status") == "skip" }
            expect(skipped).to all have_test_tag(:itr_skipped_by_itr, "true")
          end

          it "sends test session level tags" do
            expect(test_session_span).to have_test_tag(:itr_test_skipping_enabled, "true")
            expect(test_session_span).to have_test_tag(:itr_test_skipping_type, "test")
            expect(test_session_span).to have_test_tag(:itr_tests_skipped, "true")
            expect(test_session_span).to have_test_tag(:itr_test_skipping_count, 3)
          end
        end
      end

      context "skipped suite" do
        before(:context) do
          Minitest::Runnable.reset

          class SkippedTest < Minitest::Test
            def test_1
              skip
            end

            def test_2
              skip
            end
          end
        end

        it "marks all test spans as skipped" do
          expect(test_spans).to have(2).items
          expect(test_spans).to all have_skip_status
        end

        it "marks test session as passed" do
          expect(test_session_span).to have_pass_status
        end

        it "marks test suite as skipped" do
          expect(first_test_suite_span).to have_skip_status
        end
      end

      context "unskippable suite" do
        before(:context) do
          Minitest::Runnable.reset

          class UnskippableTest < Minitest::Test
            datadog_itr_unskippable

            def test_1
            end

            def test_2
            end
          end

          class ActuallySkippableTest < Minitest::Test
            def test_1
            end
          end
        end

        let(:itr_skippable_tests) do
          Set.new(
            [
              "UnskippableTest at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb.test_1.",
              "UnskippableTest at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb.test_2.",
              "ActuallySkippableTest at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb.test_1."
            ]
          )
        end

        it "runs all tests in unskippable suite and sets forced run tag" do
          expect(test_spans).to have(3).items
          expect(test_spans).to have_tag_values_no_order(:status, ["pass", "pass", "skip"])

          unskippable = test_spans.select { |span| span.get_tag("test.status") == "pass" }
          expect(unskippable).to all have_test_tag(:itr_forced_run, "true")

          expect(test_session_span).to have_test_tag(:itr_tests_skipped, "true")
          expect(test_session_span).to have_test_tag(:itr_test_skipping_count, 1)
        end
      end

      context "partially unskippable suite" do
        before(:context) do
          Minitest::Runnable.reset

          class PartiallyUnskippableTest < Minitest::Test
            datadog_itr_unskippable "test_1"

            def test_1
            end

            def test_2
            end
          end
        end

        let(:itr_skippable_tests) do
          Set.new(
            [
              "PartiallyUnskippableTest at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb.test_1.",
              "PartiallyUnskippableTest at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb.test_2."
            ]
          )
        end

        it "runs unskippable test and sets forced run tag" do
          expect(test_spans).to have(2).items
          expect(test_spans).to have_tag_values_no_order(:status, ["pass", "skip"])

          unskippable = test_spans.select { |span| span.get_tag("test.status") == "pass" }
          expect(unskippable).to all have_test_tag(:itr_forced_run, "true")

          expect(test_session_span).to have_test_tag(:itr_tests_skipped, "true")
          expect(test_session_span).to have_test_tag(:itr_test_skipping_count, 1)
        end
      end

      context "partially unskippable suite with Minitest::Spec" do
        before(:context) do
          Minitest::Runnable.reset

          class SomeUnskippableSpec < Minitest::Spec
            datadog_itr_unskippable

            it "does not fail" do
            end

            minitest_describe "in context" do
              datadog_itr_unskippable

              it "does not fail" do
              end
            end
          end
        end

        let(:itr_skippable_tests) do
          Set.new(
            [
              "SomeUnskippableSpec at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb.test_0001_does not fail.",
              "SomeUnskippableSpec::in context at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb.test_0001_does not fail."
            ]
          )
        end

        it "runs unskippable test and sets forced run tag" do
          expect(test_spans).to have(2).items
          expect(test_spans).to all have_pass_status

          expect(test_spans).to all have_test_tag(:itr_forced_run, "true")

          expect(test_session_span).to have_test_tag(:itr_tests_skipped, "false")
          expect(test_session_span).to have_test_tag(:itr_test_skipping_count, 0)
        end
      end
    end
  end

  context "when using single threaded code coverage" do
    include_context "CI mode activated" do
      let(:integration_name) { :minitest }

      let(:itr_enabled) { true }
      let(:code_coverage_enabled) { true }
      let(:use_single_threaded_coverage) { true }
    end

    before do
      Minitest.run([])
    end

    before(:context) do
      Thread.current[:dd_coverage_collector] = nil

      Minitest::Runnable.reset

      require_relative "helpers/addition_helper"
      class SomeTestWithThreads < Minitest::Test
        def test_with_background_thread
          # add thread to test that code coverage is collected
          t = Thread.new do
            AdditionHelper.add(1, 2)
          end
          t.join
          assert true
        end
      end
    end

    it "does not cover the background thread" do
      skip if PlatformHelpers.jruby?

      expect(test_spans).to have(1).item
      expect(coverage_events).to have(1).item

      # expect that background thread is not covered
      cov_event = find_coverage_for_test(first_test_span)
      expect(cov_event.coverage.keys).not_to include(
        absolute_path("helpers/addition_helper.rb")
      )
    end
  end

  context "with flaky test and test retries enabled" do
    include_context "CI mode activated" do
      let(:integration_name) { :minitest }

      let(:flaky_test_retries_enabled) { true }
    end

    before do
      Minitest.run([])
    end

    before(:context) do
      Minitest::Runnable.reset

      class FlakyTestSuite < Minitest::Test
        @@max_flaky_test_failures = 4
        @@flaky_test_failures = 0

        def test_passed
          assert true
        end

        def test_flaky
          if @@flaky_test_failures < @@max_flaky_test_failures
            @@flaky_test_failures += 1
            assert 1 + 1 == 3
          else
            assert 1 + 1 == 2
          end
        end
      end
    end

    it "retries flaky test" do
      # 1 initial run of flaky test + 4 retries until pass + 1 passing test = 6 spans
      expect(test_spans).to have(6).items

      failed_spans, passed_spans = test_spans.partition { |span| span.get_tag("test.status") == "fail" }
      expect(failed_spans).to have(4).items
      expect(passed_spans).to have(2).items

      test_spans_by_test_name = test_spans.group_by { |span| span.get_tag("test.name") }
      expect(test_spans_by_test_name["test_flaky"]).to have(5).items

      # count how many spans were marked as retries
      retries_count = test_spans.count { |span| span.get_tag("test.is_retry") == "true" }
      expect(retries_count).to eq(4)

      # check retry reasons
      retry_reasons = test_spans.map { |span| span.get_tag("test.retry_reason") }.compact
      expect(retry_reasons).to eq([Datadog::CI::Ext::Test::RetryReason::RETRY_FAILED] * 4)

      expect(test_spans_by_test_name["test_passed"]).to have(1).item

      expect(test_suite_spans).to have(1).item
      expect(test_suite_spans.first).to have_pass_status

      expect(test_session_span).to have_pass_status
    end
  end

  context "with flaky test and test retries enabled with insufficient max retries" do
    include_context "CI mode activated" do
      let(:integration_name) { :minitest }

      let(:flaky_test_retries_enabled) { true }
      let(:retry_failed_tests_max_attempts) { 3 }
    end

    before do
      Minitest.run([])
    end

    before(:context) do
      Minitest::Runnable.reset

      class FlakyTestSuite2 < Minitest::Test
        @@max_flaky_test_failures = 4
        @@flaky_test_failures = 0

        def test_passed
          assert true
        end

        def test_flaky
          if @@flaky_test_failures < @@max_flaky_test_failures
            @@flaky_test_failures += 1
            assert 1 + 1 == 3
          else
            assert 1 + 1 == 2
          end
        end
      end
    end

    it "retries flaky test without success" do
      # 1 initial run of flaky test + 3 retries without success + 1 passing test = 5 spans
      expect(test_spans).to have(5).items

      failed_spans, passed_spans = test_spans.partition { |span| span.get_tag("test.status") == "fail" }
      expect(failed_spans).to have(4).items
      expect(passed_spans).to have(1).items

      test_spans_by_test_name = test_spans.group_by { |span| span.get_tag("test.name") }
      expect(test_spans_by_test_name["test_flaky"]).to have(4).items

      # count how many spans were marked as retries
      retries_count = test_spans.count { |span| span.get_tag("test.is_retry") == "true" }
      expect(retries_count).to eq(3)

      # check retry reasons
      retry_reasons = test_spans.map { |span| span.get_tag("test.retry_reason") }.compact
      expect(retry_reasons).to eq([Datadog::CI::Ext::Test::RetryReason::RETRY_FAILED] * 3)

      expect(test_spans_by_test_name["test_passed"]).to have(1).item

      expect(test_suite_spans).to have(1).item
      expect(test_suite_spans.first).to have_fail_status

      expect(test_session_span).to have_fail_status
    end
  end

  context "with failed test, flaky test, test retries enabled, and low overall failed tests retry limit" do
    include_context "CI mode activated" do
      let(:integration_name) { :minitest }

      let(:flaky_test_retries_enabled) { true }
      let(:retry_failed_tests_total_limit) { 1 }
    end

    before do
      Minitest.run([])
    end

    before(:context) do
      Minitest::Runnable.reset

      class FailedAndFlakyTestSuite < Minitest::Test
        # yep, this test is indeed order dependent!
        i_suck_and_my_tests_are_order_dependent!

        @@max_flaky_test_failures = 4
        @@flaky_test_failures = 0

        def test_failed
          assert 1 + 1 == 4
        end

        def test_flaky
          if @@flaky_test_failures < @@max_flaky_test_failures
            @@flaky_test_failures += 1
            assert 1 + 1 == 3
          else
            assert 1 + 1 == 2
          end
        end

        def test_passed
          assert true
        end
      end
    end

    it "retries flaky test without success" do
      # 1 initial run of failed test + 5 retries without success + 1 run of flaky test without retries + 1 passing test = 8 spans
      expect(test_spans).to have(8).items

      failed_spans, passed_spans = test_spans.partition { |span| span.get_tag("test.status") == "fail" }
      expect(failed_spans).to have(7).items
      expect(passed_spans).to have(1).items

      test_spans_by_test_name = test_spans.group_by { |span| span.get_tag("test.name") }
      expect(test_spans_by_test_name["test_flaky"]).to have(1).item
      expect(test_spans_by_test_name["test_failed"]).to have(6).items
      expect(test_spans_by_test_name["test_passed"]).to have(1).item

      # count how many spans were marked as retries
      retries_count = test_spans.count { |span| span.get_tag("test.is_retry") == "true" }
      expect(retries_count).to eq(5)

      # check retry reasons
      retry_reasons = test_spans.map { |span| span.get_tag("test.retry_reason") }.compact
      expect(retry_reasons).to eq([Datadog::CI::Ext::Test::RetryReason::RETRY_FAILED] * 5)

      expect(test_suite_spans).to have(1).item
      expect(test_suite_spans.first).to have_fail_status

      expect(test_session_span).to have_fail_status
    end
  end

  context "with flaky test, test retries enabled, and threading test runner" do
    include_context "CI mode activated" do
      let(:integration_name) { :minitest }

      let(:flaky_test_retries_enabled) { true }
    end

    before do
      Minitest.run([])
    end

    before(:context) do
      Minitest::Runnable.reset

      class ParallelFlakyTestSuite < Minitest::Test
        parallelize_me!

        @@max_flaky_test_failures = 4
        @@flaky_test_failures = 0

        def test_passed
          assert true
        end

        def test_flaky
          if @@flaky_test_failures < @@max_flaky_test_failures
            @@flaky_test_failures += 1
            assert 1 + 1 == 3
          else
            assert 1 + 1 == 2
          end
        end

        def test_failed
          assert 1 + 1 == 4
        end
      end
    end

    it "retries flaky test" do
      # 1 initial run of flaky test + 4 retries until pass + 1 failed test run + 5 retries + 1 passing test = 12 spans
      expect(test_spans).to have(12).items

      failed_spans, passed_spans = test_spans.partition { |span| span.get_tag("test.status") == "fail" }
      expect(failed_spans).to have(10).items
      expect(passed_spans).to have(2).items

      test_spans_by_test_name = test_spans.group_by { |span| span.get_tag("test.name") }
      expect(test_spans_by_test_name["test_flaky"]).to have(5).items

      # count how many spans were marked as retries
      retries_count = test_spans.count { |span| span.get_tag("test.is_retry") == "true" }
      expect(retries_count).to eq(9)

      # check retry reasons
      retry_reasons = test_spans.map { |span| span.get_tag("test.retry_reason") }.compact
      expect(retry_reasons).to eq([Datadog::CI::Ext::Test::RetryReason::RETRY_FAILED] * 9)

      # last retry is tagged with has_failed_all_retries for test_failed
      failed_all_retries_count = test_spans.count { |span| span.get_tag("test.has_failed_all_retries") }
      expect(failed_all_retries_count).to eq(1)

      expect(test_spans_by_test_name["test_passed"]).to have(1).item

      expect(test_suite_spans).to have(1).item

      expect(test_session_span).to have_fail_status
    end
  end

  context "with one new test and new test retries enabled" do
    include_context "CI mode activated" do
      let(:integration_name) { :minitest }

      let(:early_flake_detection_enabled) { true }
      let(:known_tests) { Set.new(["TestSuiteWithNewTest at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb.test_passed."]) }
    end

    before do
      Minitest.run([])
    end

    before(:context) do
      Minitest::Runnable.reset

      class TestSuiteWithNewTest < Minitest::Test
        def test_passed
          assert true
        end

        def test_passed_second
          assert true
        end
      end
    end

    it "retries new test" do
      # 1 initial run of test_passed + 1 run of test_passed_second + 10 retries = 12 spans
      expect(test_spans).to have(12).items

      test_spans_by_test_name = test_spans.group_by { |span| span.get_tag("test.name") }
      expect(test_spans_by_test_name["test_passed"]).to have(1).item
      expect(test_spans_by_test_name["test_passed_second"]).to have(11).items

      # count how many spans were marked as retries
      retries_count = test_spans.count { |span| span.get_tag("test.is_retry") == "true" }
      expect(retries_count).to eq(10)

      # check retry reasons
      retry_reasons = test_spans.map { |span| span.get_tag("test.retry_reason") }.compact
      expect(retry_reasons).to eq([Datadog::CI::Ext::Test::RetryReason::RETRY_DETECT_FLAKY] * 10)

      # count how many tests were marked as new
      new_tests_count = test_spans.count { |span| span.get_tag("test.is_new") == "true" }
      expect(new_tests_count).to eq(11)

      expect(test_suite_spans).to have(1).item
      expect(test_suite_spans.first).to have_pass_status

      expect(test_session_span).to have_pass_status
      expect(test_session_span).to have_test_tag(:early_flake_enabled, "true")
      expect(test_session_span).to_not have_test_tag(:early_flake_abort_reason)
    end
  end

  context "when all tests are new" do
    include_context "CI mode activated" do
      let(:integration_name) { :minitest }

      let(:early_flake_detection_enabled) { true }
      let(:known_tests) { Set.new(["TestSuiteWithNewTest at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb.no_such_test."]) }
      let(:faulty_session_threshold) { 10 }
    end

    before do
      Minitest.run([])
    end

    before(:context) do
      Minitest::Runnable.reset

      class TestSuiteWithFaultyEFDTest < Minitest::Test
        def test_passed
          assert true
        end

        def test_passed_second
          assert true
        end
      end
    end

    it "bails out of retrying new tests and marks EFD as faulty" do
      # 1 initial run of a test + 10 retries + 1 run of another test = 12 spans
      expect(test_spans).to have(12).items

      # count how many spans were marked as retries
      retries_count = test_spans.count { |span| span.get_tag("test.is_retry") == "true" }
      expect(retries_count).to eq(10)

      # check retry reasons
      retry_reasons = test_spans.map { |span| span.get_tag("test.retry_reason") }.compact
      expect(retry_reasons).to eq([Datadog::CI::Ext::Test::RetryReason::RETRY_DETECT_FLAKY] * 10)

      # count how many tests were marked as new
      new_tests_count = test_spans.count { |span| span.get_tag("test.is_new") == "true" }
      expect(new_tests_count).to eq(12)

      expect(test_suite_spans).to have(1).item
      expect(test_suite_spans.first).to have_pass_status

      expect(test_session_span).to have_pass_status
      expect(test_session_span).to have_test_tag(:early_flake_enabled, "true")
      expect(test_session_span).to have_test_tag(:early_flake_abort_reason, "faulty")
    end
  end

  context "with new test retries enabled and there is a test that fails once on the last retry" do
    include_context "CI mode activated" do
      let(:integration_name) { :minitest }

      let(:early_flake_detection_enabled) { true }
      let(:known_tests) { Set.new(["FlakyTestThatFailsOnceSuite at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb.test_passed."]) }
    end

    before do
      Minitest.run([])
    end

    before(:context) do
      Minitest::Runnable.reset

      class FlakyTestThatFailsOnceSuite < Minitest::Test
        @@max_flaky_test_passes = 10
        @@flaky_test_passes = 0

        def test_passed
          assert true
        end

        def test_flaky
          if @@flaky_test_passes < @@max_flaky_test_passes
            @@flaky_test_passes += 1
            assert 1 + 1 == 2
          else
            assert 1 + 1 == 3
          end
        end
      end
    end

    it "does not fail the build" do
      # 1 initial run of new test + 10 retries + 1 passing test = 12 spans
      expect(test_spans).to have(12).items

      failed_spans, passed_spans = test_spans.partition { |span| span.get_tag("test.status") == "fail" }
      expect(failed_spans).to have(1).items
      expect(passed_spans).to have(11).items

      test_spans_by_test_name = test_spans.group_by { |span| span.get_tag("test.name") }
      expect(test_spans_by_test_name["test_flaky"]).to have(11).item
      expect(test_spans_by_test_name["test_passed"]).to have(1).item

      # count how many spans were marked as retries
      retries_count = test_spans.count { |span| span.get_tag("test.is_retry") == "true" }
      expect(retries_count).to eq(10)

      # check retry reasons
      retry_reasons = test_spans.map { |span| span.get_tag("test.retry_reason") }.compact
      expect(retry_reasons).to eq([Datadog::CI::Ext::Test::RetryReason::RETRY_DETECT_FLAKY] * 10)

      # count how many tests were marked as new
      new_tests_count = test_spans.count { |span| span.get_tag("test.is_new") == "true" }
      expect(new_tests_count).to eq(11)

      expect(test_suite_spans).to have(1).item
      expect(test_suite_spans.first).to have_pass_status

      expect(test_session_span).to have_pass_status
      expect(test_session_span).to have_test_tag(:early_flake_enabled, "true")
    end
  end

  context "with test management enabled and one quarantined test" do
    include_context "CI mode activated" do
      let(:integration_name) { :minitest }

      let(:test_management_enabled) { true }
      let(:test_properties) do
        {
          "QuarantinedTestSuite at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb.test_failed." => {
            "quarantined" => true,
            "disabled" => false,
            "attempt_to_fix" => false
          }
        }
      end
    end

    before do
      Minitest.run([])
    end

    before(:context) do
      Minitest::Runnable.reset

      class QuarantinedTestSuite < Minitest::Test
        def test_passed
          assert true
        end

        def test_failed
          assert 1 + 1 == 3
        end
      end
    end

    it "runs failing test but does not fail the build" do
      expect(test_spans).to have(2).items

      quarantined_test_span = test_spans.find { |span| span.name == "test_failed" }

      expect(quarantined_test_span).to have_fail_status
      expect(quarantined_test_span).to have_test_tag(:is_quarantined)
      expect(quarantined_test_span).not_to have_test_tag(:is_test_disabled)
      expect(quarantined_test_span).not_to have_test_tag(:is_attempt_to_fix)

      # as there are no retries, there is no has_failed_all_retries tag
      failed_all_retries_count = test_spans.count { |span| span.get_tag("test.has_failed_all_retries") }
      expect(failed_all_retries_count).to eq(0)

      expect(test_suite_spans).to have(1).item
      expect(test_suite_spans.first).to have_pass_status

      expect(test_session_span).to have_pass_status
      expect(test_session_span).to have_test_tag(:test_management_enabled, "true")
    end
  end

  context "with test management enabled and a disabled test" do
    include_context "CI mode activated" do
      let(:integration_name) { :minitest }

      let(:test_management_enabled) { true }
      let(:test_properties) do
        {
          "DisabledTestSuite at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb.test_failed." => {
            "quarantined" => false,
            "disabled" => true,
            "attempt_to_fix" => false
          }
        }
      end
    end

    before do
      Minitest.run([])
    end

    before(:context) do
      Minitest::Runnable.reset

      class DisabledTestSuite < Minitest::Test
        def test_passed
          assert true
        end

        def test_failed
          assert 1 + 1 == 3
        end
      end
    end

    it "skips the disabled test completely" do
      expect(test_spans).to have(2).items

      disabled_test_span = test_spans.find { |span| span.name == "test_failed" }

      expect(disabled_test_span).to have_skip_status
      expect(disabled_test_span).to have_test_tag(:skip_reason, "Flaky test is disabled by Datadog")
      expect(disabled_test_span).not_to have_test_tag(:is_quarantined)
      expect(disabled_test_span).to have_test_tag(:is_test_disabled)
      expect(disabled_test_span).not_to have_test_tag(:is_attempt_to_fix)

      expect(test_suite_spans).to have(1).item
      expect(test_suite_spans.first).to have_pass_status

      expect(test_session_span).to have_pass_status
      expect(test_session_span).to have_test_tag(:test_management_enabled, "true")
    end
  end

  context "with test management enabled and a test attempted to be fixed" do
    include_context "CI mode activated" do
      let(:integration_name) { :minitest }

      let(:test_management_enabled) { true }
      let(:test_properties) do
        {
          "AttemptToFixTestSuite at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb.test_failed." => {
            "quarantined" => true,
            "disabled" => false,
            "attempt_to_fix" => true
          }
        }
      end
    end

    before do
      Minitest.run([])
    end

    before(:context) do
      Minitest::Runnable.reset

      class AttemptToFixTestSuite < Minitest::Test
        def test_passed
          assert true
        end

        def test_failed
          assert 1 + 1 == 3
        end
      end
    end

    it "runs failing test and retries it but does not fail the build" do
      # 1 original execution and 12 retries (attempt_to_fix_retries_count) and one passed test
      expect(test_spans).to have(attempt_to_fix_retries_count + 2).items

      failed_spans, passed_spans = test_spans.partition { |span| span.get_tag("test.status") == "fail" }
      expect(failed_spans).to have(attempt_to_fix_retries_count + 1).items
      expect(passed_spans).to have(1).item

      # count how many tests were marked as retries
      retries_count = test_spans.count { |span| span.get_tag("test.is_retry") == "true" }
      expect(retries_count).to eq(attempt_to_fix_retries_count)

      # check retry reasons
      retry_reasons = test_spans.map { |span| span.get_tag("test.retry_reason") }.compact
      expect(retry_reasons).to eq(["attempt_to_fix"] * attempt_to_fix_retries_count)

      # count how many tests were marked as attempt_to_fix
      attempt_to_fix_count = test_spans.count { |span| span.get_tag("test.test_management.is_attempt_to_fix") == "true" }
      expect(attempt_to_fix_count).to eq(attempt_to_fix_retries_count + 1)

      # count how many tests were marked as quarantined
      quarantined_count = test_spans.count { |span| span.get_tag("test.test_management.is_quarantined") == "true" }
      expect(quarantined_count).to eq(attempt_to_fix_retries_count + 1)

      # last retry is tagged with has_failed_all_retries
      failed_all_retries_count = test_spans.count { |span| span.get_tag("test.has_failed_all_retries") }
      expect(failed_all_retries_count).to eq(1)

      fix_passed_successfully_tests_count = test_spans.count { |span| span.get_tag("test.test_management.attempt_to_fix_passed") == "true" }
      expect(fix_passed_successfully_tests_count).to eq(0)

      fix_failed_tests_count = test_spans.count { |span| span.get_tag("test.test_management.attempt_to_fix_passed") == "false" }
      expect(fix_failed_tests_count).to eq(1)

      expect(test_suite_spans).to have(1).item
      expect(test_suite_spans.first).to have_pass_status

      expect(test_session_span).to have_pass_status
      expect(test_session_span).to have_test_tag(:test_management_enabled, "true")
    end
  end

  context "session with early flake detection and impacted tests detection enabled" do
    include_context "CI mode activated" do
      let(:integration_name) { :minitest }

      let(:early_flake_detection_enabled) { true }
      let(:impacted_tests_enabled) { true }
      let(:faulty_session_threshold) { 100 }

      let(:known_tests) do
        Set.new(["TestSuiteWithModifiedTest at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb.test_passed."])
      end
      let(:changed_files) do
        Set.new([
          "spec/datadog/ci/contrib/minitest/instrumentation_spec.rb:1622:1622"
        ])
      end
    end
    before do
      Minitest.run([])
    end

    before(:context) do
      Minitest::Runnable.reset

      class TestSuiteWithModifiedTest < Minitest::Test
        def test_passed
          assert true
        end
      end
    end

    it "retries each of the modified tests 10 times" do
      expect(test_spans).to have(11).items

      # count how many tests were marked as retries
      retries_count = test_spans.count { |span| span.get_tag("test.is_retry") == "true" }
      expect(retries_count).to eq(10)

      # check retry reasons
      retry_reasons = test_spans.map { |span| span.get_tag("test.retry_reason") }.compact
      expect(retry_reasons).to eq(["early_flake_detection"] * 10)

      # count how many test spans were marked as modified
      modified_count = test_spans.count { |span| span.get_tag("test.is_modified") == "true" }
      expect(modified_count).to eq(11)

      expect(test_suite_spans).to have(1).item
      expect(test_suite_spans.first).to have_pass_status

      expect(test_session_span).to have_pass_status
    end
  end

  context "test_suite_name method with path handling" do
    it "handles relative paths as-is" do
      klass = Class.new(Minitest::Test) do
        def self.name
          "RelativePathTest"
        end

        def test_method
        end
      end

      # Mock the instance_method to return relative path
      method_double = double("method")
      allow(method_double).to receive(:source_location).and_return(["relative/path/to/test.rb", 10])
      allow(klass).to receive(:instance_method).with(:test_method).and_return(method_double)

      # Mock extract_source_location_from_class to return nil (to trigger fallback)
      allow(Datadog::CI::Contrib::Minitest::Helpers).to receive(:extract_source_location_from_class).with(klass).and_return([])

      suite_name = Datadog::CI::Contrib::Minitest::Helpers.test_suite_name(klass, :test_method)
      expect(suite_name).to eq("RelativePathTest at relative/path/to/test.rb")
    end
  end
end
