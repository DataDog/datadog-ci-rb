require "time"

require "minitest"
require "minitest/spec"

# minitest adds `describe` method to Kernel, which conflicts with RSpec.
# here we define `minitest_describe` method to avoid this conflict.
module Kernel
  alias_method :minitest_describe, :describe
end

RSpec.describe "Minitest instrumentation" do
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

  context "with service name configured" do
    include_context "CI mode activated" do
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
        Datadog::CI::Contrib::Minitest::Integration.version.to_s
      )

      expect(span).to have_pass_status

      expect(span).to have_test_tag(
        :source_file,
        "spec/datadog/ci/contrib/minitest/instrumentation_spec.rb"
      )
      expect(span).to have_test_tag(:source_start, "51")
      expect(span).to have_test_tag(
        :codeowners,
        "[\"@DataDog/ruby-guild\", \"@DataDog/ci-app-libraries\"]"
      )
    end

    it "creates spans for several tests" do
      expect(Datadog::CI::Ext::Environment).to receive(:tags).never

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
      before do
        Minitest.run([])
      end

      context "passed tests" do
        before(:context) do
          Minitest::Runnable.reset

          class SomeTest < Minitest::Test
            def test_pass
              assert true
            end

            def test_pass_other
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
            Datadog::CI::Contrib::Minitest::Integration.version.to_s
          )

          # ITR
          expect(test_session_span).to have_test_tag(:itr_test_skipping_enabled, "true")
          expect(test_session_span).to have_test_tag(:itr_test_skipping_type, "test")
          expect(test_session_span).to have_test_tag(:itr_tests_skipped, "false")
          expect(test_session_span).to have_test_tag(:itr_test_skipping_count, 0)

          expect(test_session_span).to have_pass_status
        end

        it "creates a test module span" do
          expect(test_module_span).not_to be_nil

          expect(test_module_span.type).to eq("test_module_end")
          expect(test_module_span.name).to eq("minitest")

          expect(test_module_span).to have_test_tag(:span_kind, "test")
          expect(test_module_span).to have_test_tag(:framework, "minitest")
          expect(test_module_span).to have_test_tag(
            :framework_version,
            Datadog::CI::Contrib::Minitest::Integration.version.to_s
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
            Datadog::CI::Contrib::Minitest::Integration.version.to_s
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
            Datadog::CI::Contrib::Minitest::Integration.version.to_s
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
        end

        context "when ITR skips tests" do
          context "single skipped test" do
            let(:itr_skippable_tests) do
              Set.new(["SomeTest at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb.test_pass"])
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
                  "SomeTest at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb.test_pass",
                  "SomeTest at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb.test_pass_other"
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
              "in context at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb",
              "in context::deeper context at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb",
              "in other context at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb"
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

        it "traces all tests correctly, assigning a separate test suite to each of them" do
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
          expect(test_spans).to have_unique_tag_values_count(:test_suite_id, 4)
        end

        it "connects tests to a single test session and a single test module" do
          expect(test_spans).to have_unique_tag_values_count(:test_module_id, 1)
          expect(test_spans).to have_unique_tag_values_count(:test_session_id, 1)

          expect(first_test_span).to have_test_tag(:test_module_id, test_module_span.id.to_s)
          expect(first_test_span).to have_test_tag(:test_session_id, test_session_span.id.to_s)
        end

        it "correctly tracks test and session durations" do
          test_session_duration = test_session_span.duration

          test_durations_sum = test_spans.map { |span| span.duration }.sum
          # with parallel execution test durations sum should be greater than test session duration
          expect(test_durations_sum).to be > test_session_duration

          # each individual test duration should be less than test session duration
          test_spans.each do |span|
            expect(span.duration).to be < test_session_duration
          end
        end

        it "creates test suite spans" do
          expect(test_suite_spans).to have(4).items

          expect(test_suite_spans).to have_tag_values_no_order(
            :suite,
            [
              "TestA at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb (test_a_1 concurrently)",
              "TestA at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb (test_a_2 concurrently)",
              "TestB at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb (test_b_1 concurrently)",
              "TestB at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb (test_b_2 concurrently)"
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

        context "when ITR skips tests" do
          let(:itr_skippable_tests) do
            Set.new(
              [
                "TestA at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb (test_a_1 concurrently).test_a_1",
                "TestA at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb (test_a_2 concurrently).test_a_2",
                "TestB at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb (test_b_2 concurrently).test_b_2"
              ]
            )
          end

          it "skips given tests" do
            expect(test_spans).to have(4).items
            expect(test_spans).to have_tag_values_no_order(:status, ["skip", "skip", "skip", "pass"])

            skipped = test_spans.select { |span| span.get_tag("status") == "skip" }
            expect(skipped).to all have_test_tag(:itr_skipped_by_itr, "true")
          end

          it "send test session level tags" do
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
    end
  end
end
