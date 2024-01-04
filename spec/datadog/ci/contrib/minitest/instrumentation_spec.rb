require "time"

require "minitest"
require "minitest/spec"

# minitest adds `describe` method to Kernel, which conflicts with RSpec.
# here we define `minitest_describe` method to avoid this conflict.
module Kernel
  alias_method :minitest_describe, :describe
end

RSpec.describe "Minitest instrumentation" do
  include_context "CI mode activated" do
    let(:integration_name) { :minitest }
    let(:integration_options) { {service_name: "ltest"} }
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

    expect(span.span_type).to eq(Datadog::CI::Ext::AppTypes::TYPE_TEST)
    expect(span.name).to eq("SomeTest#test_foo")
    expect(span.resource).to eq("SomeTest#test_foo")
    expect(span.service).to eq("ltest")
    expect(span.get_tag(Datadog::CI::Ext::Test::TAG_NAME)).to eq("SomeTest#test_foo")
    expect(span.get_tag(Datadog::CI::Ext::Test::TAG_SUITE)).to eq(
      "SomeTest at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb"
    )
    expect(span.get_tag(Datadog::CI::Ext::Test::TAG_SPAN_KIND)).to eq(Datadog::CI::Ext::AppTypes::TYPE_TEST)
    expect(span.get_tag(Datadog::CI::Ext::Test::TAG_TYPE)).to eq(Datadog::CI::Ext::Test::TEST_TYPE)
    expect(span.get_tag(Datadog::CI::Ext::Test::TAG_FRAMEWORK)).to eq(Datadog::CI::Contrib::Minitest::Ext::FRAMEWORK)
    expect(span.get_tag(Datadog::CI::Ext::Test::TAG_FRAMEWORK_VERSION)).to eq(
      Datadog::CI::Contrib::Minitest::Integration.version.to_s
    )
    expect(span.get_tag(Datadog::CI::Ext::Test::TAG_STATUS)).to eq(Datadog::CI::Ext::Test::Status::PASS)
    expect(span.get_tag(Datadog::CI::Ext::Test::TAG_SOURCE_FILE)).to eq(
      "spec/datadog/ci/contrib/minitest/instrumentation_spec.rb"
    )
    expect(span.get_tag(Datadog::CI::Ext::Test::TAG_SOURCE_START)).to eq("29")
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

    expect(span.span_type).to eq(Datadog::CI::Ext::AppTypes::TYPE_TEST)
    expect(span.resource).to eq("SomeSpec##{method_name}")
    expect(span.service).to eq("ltest")
    expect(span.get_tag(Datadog::CI::Ext::Test::TAG_NAME)).to eq("SomeSpec##{method_name}")
    expect(span.get_tag(Datadog::CI::Ext::Test::TAG_SUITE)).to eq(
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

    spans.each do |span|
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::Distributed::TAG_ORIGIN))
        .to eq(Datadog::CI::Ext::Test::CONTEXT_ORIGIN)
    end
  end

  context "catches failures" do
    def expect_failure
      expect(span.get_tag(Datadog::CI::Ext::Test::TAG_STATUS)).to eq(Datadog::CI::Ext::Test::Status::FAIL)
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
      expect(span.get_tag(Datadog::CI::Ext::Test::TAG_STATUS)).to eq(Datadog::CI::Ext::Test::Status::FAIL)
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
      expect(span.get_tag(Datadog::CI::Ext::Test::TAG_STATUS)).to eq(Datadog::CI::Ext::Test::Status::SKIP)
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
      expect(span.get_tag(Datadog::CI::Ext::Test::TAG_SKIP_REASON)).to eq("Skip!")
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
      expect(span.get_tag(Datadog::CI::Ext::Test::TAG_SKIP_REASON)).to eq("Skipped, no message given")
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

    context "single test passed" do
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
        expect(test_session_span.span_type).to eq(Datadog::CI::Ext::AppTypes::TYPE_TEST_SESSION)
        expect(test_session_span.get_tag(Datadog::CI::Ext::Test::TAG_SPAN_KIND)).to eq(
          Datadog::CI::Ext::AppTypes::TYPE_TEST
        )
        expect(test_session_span.get_tag(Datadog::CI::Ext::Test::TAG_TYPE)).to eq(
          Datadog::CI::Ext::Test::TEST_TYPE
        )
        expect(test_session_span.get_tag(Datadog::CI::Ext::Test::TAG_FRAMEWORK)).to eq(
          Datadog::CI::Contrib::Minitest::Ext::FRAMEWORK
        )
        expect(test_session_span.get_tag(Datadog::CI::Ext::Test::TAG_FRAMEWORK_VERSION)).to eq(
          Datadog::CI::Contrib::Minitest::Integration.version.to_s
        )
        expect(test_session_span.get_tag(Datadog::CI::Ext::Test::TAG_STATUS)).to eq(
          Datadog::CI::Ext::Test::Status::PASS
        )
      end

      it "creates a test module span" do
        expect(test_module_span).not_to be_nil

        expect(test_module_span.span_type).to eq(Datadog::CI::Ext::AppTypes::TYPE_TEST_MODULE)
        expect(test_module_span.name).to eq(test_command)

        expect(test_module_span.get_tag(Datadog::CI::Ext::Test::TAG_SPAN_KIND)).to eq(
          Datadog::CI::Ext::AppTypes::TYPE_TEST
        )
        expect(test_module_span.get_tag(Datadog::CI::Ext::Test::TAG_TYPE)).to eq(
          Datadog::CI::Ext::Test::TEST_TYPE
        )
        expect(test_module_span.get_tag(Datadog::CI::Ext::Test::TAG_FRAMEWORK)).to eq(
          Datadog::CI::Contrib::Minitest::Ext::FRAMEWORK
        )
        expect(test_module_span.get_tag(Datadog::CI::Ext::Test::TAG_FRAMEWORK_VERSION)).to eq(
          Datadog::CI::Contrib::Minitest::Integration.version.to_s
        )
        expect(test_module_span.get_tag(Datadog::CI::Ext::Test::TAG_STATUS)).to eq(
          Datadog::CI::Ext::Test::Status::PASS
        )
      end

      it "creates a test suite span" do
        expect(test_suite_span).not_to be_nil

        expect(test_suite_span.span_type).to eq(Datadog::CI::Ext::AppTypes::TYPE_TEST_SUITE)
        expect(test_suite_span.name).to eq("SomeTest at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb")

        expect(test_suite_span.get_tag(Datadog::CI::Ext::Test::TAG_SPAN_KIND)).to eq(
          Datadog::CI::Ext::AppTypes::TYPE_TEST
        )
        expect(test_suite_span.get_tag(Datadog::CI::Ext::Test::TAG_TYPE)).to eq(
          Datadog::CI::Ext::Test::TEST_TYPE
        )
        expect(test_suite_span.get_tag(Datadog::CI::Ext::Test::TAG_FRAMEWORK)).to eq(
          Datadog::CI::Contrib::Minitest::Ext::FRAMEWORK
        )
        expect(test_suite_span.get_tag(Datadog::CI::Ext::Test::TAG_FRAMEWORK_VERSION)).to eq(
          Datadog::CI::Contrib::Minitest::Integration.version.to_s
        )
        expect(test_suite_span.get_tag(Datadog::CI::Ext::Test::TAG_STATUS)).to eq(
          Datadog::CI::Ext::Test::Status::PASS
        )
      end

      it "creates test spans and connects them to the session, module, and suite" do
        expect(test_spans.count).to eq(2)

        expect(first_test_span.get_tag(Datadog::CI::Ext::Test::TAG_SUITE)).to eq(
          "SomeTest at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb"
        )
        expect(first_test_span.get_tag(Datadog::CI::Ext::Test::TAG_FRAMEWORK)).to eq(
          Datadog::CI::Contrib::Minitest::Ext::FRAMEWORK
        )
        expect(first_test_span.get_tag(Datadog::CI::Ext::Test::TAG_FRAMEWORK_VERSION)).to eq(
          Datadog::CI::Contrib::Minitest::Integration.version.to_s
        )
        expect(first_test_span.get_tag(Datadog::CI::Ext::Test::TAG_STATUS)).to eq(
          Datadog::CI::Ext::Test::Status::PASS
        )

        test_session_ids = test_spans.map { |span| span.get_tag(Datadog::CI::Ext::Test::TAG_TEST_SESSION_ID) }.uniq
        test_module_ids = test_spans.map { |span| span.get_tag(Datadog::CI::Ext::Test::TAG_TEST_MODULE_ID) }.uniq
        test_suite_ids = test_spans.map { |span| span.get_tag(Datadog::CI::Ext::Test::TAG_TEST_SUITE_ID) }.uniq

        expect(test_session_ids.count).to eq(1)
        expect(test_session_ids.first).to eq(test_session_span.id.to_s)

        expect(test_module_ids.count).to eq(1)
        expect(test_module_ids.first).to eq(test_module_span.id.to_s)

        expect(test_suite_ids.count).to eq(1)
        expect(test_suite_ids.first).to eq(test_suite_span.id.to_s)
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
        expect(first_test_span.get_tag(Datadog::CI::Ext::Test::TAG_NAME)).to eq("SomeFailedTest#test_fail")
        expect(first_test_span.get_tag(Datadog::CI::Ext::Test::TAG_STATUS)).to eq(
          Datadog::CI::Ext::Test::Status::FAIL
        )

        expect(test_session_span.get_tag(Datadog::CI::Ext::Test::TAG_STATUS)).to eq(
          Datadog::CI::Ext::Test::Status::FAIL
        )
        expect(test_module_span.get_tag(Datadog::CI::Ext::Test::TAG_STATUS)).to eq(
          Datadog::CI::Ext::Test::Status::FAIL
        )
        expect(test_suite_span.get_tag(Datadog::CI::Ext::Test::TAG_STATUS)).to eq(
          Datadog::CI::Ext::Test::Status::FAIL
        )
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
        test_names = test_spans.map { |span| span.get_tag(Datadog::CI::Ext::Test::TAG_NAME) }.sort

        expect(test_names).to eq(
          [
            "SomeSpec#test_0001_does not fail",
            "in context#test_0001_does not fail",
            "in context::deeper context#test_0001_does not fail",
            "in other context#test_0001_does not fail"
          ]
        )
      end

      it "connects tests to different test suites (one per spec context)" do
        test_suite_ids = test_spans.map { |span| span.get_tag(Datadog::CI::Ext::Test::TAG_TEST_SUITE_ID) }.uniq
        test_suite_names = test_spans.map { |span| span.get_tag(Datadog::CI::Ext::Test::TAG_SUITE) }.sort

        expect(test_suite_ids).to have(4).items
        expect(test_suite_names).to eq(
          [
            "SomeSpec at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb",
            "in context at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb",
            "in context::deeper context at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb",
            "in other context at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb"
          ]
        )
      end

      it "connects tests to a single test session" do
        test_session_ids = test_spans.map { |span| span.get_tag(Datadog::CI::Ext::Test::TAG_TEST_SESSION_ID) }.uniq

        expect(test_session_ids.count).to eq(1)
        expect(test_session_ids.first).to eq(test_session_span.id.to_s)
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

        test_names = test_spans.map { |span| span.get_tag(Datadog::CI::Ext::Test::TAG_NAME) }.sort
        expect(test_names).to eq(
          [
            "TestA#test_a_1",
            "TestA#test_a_2",
            "TestB#test_b_1",
            "TestB#test_b_2"
          ]
        )

        test_suite_ids = test_spans.map { |span| span.get_tag(Datadog::CI::Ext::Test::TAG_TEST_SUITE_ID) }.uniq
        expect(test_suite_ids).to have(4).items
      end

      it "connects tests to a single test session and a single test module" do
        test_session_ids = test_spans.map { |span| span.get_tag(Datadog::CI::Ext::Test::TAG_TEST_SESSION_ID) }.uniq
        test_module_ids = test_spans.map { |span| span.get_tag(Datadog::CI::Ext::Test::TAG_TEST_MODULE_ID) }.uniq

        expect(test_session_ids.count).to eq(1)
        expect(test_session_ids.first).to eq(test_session_span.id.to_s)

        expect(test_module_ids.count).to eq(1)
        expect(test_module_ids.first).to eq(test_module_span.id.to_s)
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

        test_suite_names = test_suite_spans.map { |span| span.name }.sort
        expect(test_suite_names).to eq(
          [
            "TestA at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb (test_a_1 concurrently)",
            "TestA at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb (test_a_2 concurrently)",
            "TestB at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb (test_b_1 concurrently)",
            "TestB at spec/datadog/ci/contrib/minitest/instrumentation_spec.rb (test_b_2 concurrently)"
          ]
        )
      end
    end
  end
end
