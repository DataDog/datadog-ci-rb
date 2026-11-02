# frozen_string_literal: true

require "minitest"

RSpec.describe "Minitest test automation exclusions" do
  include_context "CI mode activated" do
    let(:integration_name) { :minitest }
    let(:flaky_test_retries_enabled) { true }
    let(:test_management_enabled) { true }
    let(:test_properties) { Hash.new({"quarantined" => true, "disabled" => true, "attempt_to_fix" => true}.freeze) }
  end

  before do
    test_tracing.start_test_session
    test_tracing.start_test_module("minitest")
  end

  it "keeps a protected failure blocking and omits automatic retries" do
    klass = Class.new(Minitest::Test) do
      def test_failure
        flunk "protected failure"
      end
      datadog_prevent_failure_suppression :test_failure
      datadog_no_auto_retry :test_failure
    end
    result = Minitest.run_one_method(klass, "test_failure")
    expect(result.failures.size).to eq(1)
    expect(test_spans.size).to eq(1)
    expect(first_test_span.get_tag("test.test_management.is_test_disabled")).to eq("true")
    expect(first_test_span.get_tag("test.test_management.prevent_failure_suppression")).to eq("true")
    expect(first_test_span.get_tag("test.test_management.no_auto_retry")).to eq("true")
  end

  it "clears annotations when a test declaration is replaced" do
    klass = Class.new(Minitest::Test) do
      def test_example
      end
      datadog_no_auto_retry :test_example
    end
    expect(klass.dd_test_no_auto_retry?("test_example")).to be(true)
    klass.class_eval { define_method(:test_example) {} }
    expect(klass.dd_test_no_auto_retry?("test_example")).to be(false)
  end

  it "does not apply one class's declarations to a same-named test in another class" do
    protected_class = Class.new(Minitest::Test) do
      def test_example
      end
      datadog_no_auto_retry :test_example
    end
    ordinary_class = Class.new(Minitest::Test) do
      def test_example
      end
    end
    expect(protected_class.dd_test_no_auto_retry?("test_example")).to be(true)
    expect(ordinary_class.dd_test_no_auto_retry?("test_example")).to be(false)
  end
  it "preserves an inherited individual declaration but not an overridden method" do
    parent = Class.new(Minitest::Test) do
      def test_example
      end
      datadog_no_auto_retry :test_example
    end
    child = Class.new(parent)
    expect(child.dd_test_no_auto_retry?("test_example")).to be(true)
    child.class_eval { define_method(:test_example) {} }
    expect(child.dd_test_no_auto_retry?("test_example")).to be(false)
    expect(parent.dd_test_no_auto_retry?("test_example")).to be(true)
  end

  it "keeps aliases of the same method independently annotated" do
    klass = Class.new(Minitest::Test) do
      def test_example
      end
      alias_method :test_alias, :test_example
      datadog_no_auto_retry :test_example
    end
    expect(klass.dd_test_no_auto_retry?("test_example")).to be(true)
    expect(klass.dd_test_no_auto_retry?("test_alias")).to be(false)
  end
end
