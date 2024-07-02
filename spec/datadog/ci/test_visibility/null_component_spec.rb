# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/test_visibility/null_component"

RSpec.describe Datadog::CI::TestVisibility::NullComponent do
  let(:test_visibility) { described_class.new }

  describe "#start_test_session" do
    subject { test_visibility.start_test_session }

    it { is_expected.to be_nil }

    it "does not activate session" do
      expect(test_visibility.active_test_session).to be_nil
    end
  end

  describe "#start_test_module" do
    let(:module_name) { "my-module" }

    subject { test_visibility.start_test_module(module_name) }

    it { is_expected.to be_nil }

    it "does not activate module" do
      expect(test_visibility.active_test_module).to be_nil
    end
  end

  describe "#start_test_suite" do
    let(:suite_name) { "my-module" }

    subject { test_visibility.start_test_suite(suite_name) }

    it { is_expected.to be_nil }

    it "does not activate test suite" do
      expect(test_visibility.active_test_suite(suite_name)).to be_nil
    end
  end

  describe "#trace_test" do
    context "when given a block" do
      let(:spy_under_test) { spy("spy") }

      before do
        test_visibility.trace_test("my test", "my suite") do |test_span|
          spy_under_test.call

          test_span&.passed!
        end
      end

      it "does not create spans" do
        expect(spans.count).to eq(0)
      end

      it "executes the test code" do
        expect(spy_under_test).to have_received(:call)
      end
    end

    context "without a block" do
      subject { test_visibility.trace_test("my test", "my suite") }

      it { is_expected.to be_nil }
    end
  end

  describe "#trace" do
    context "when given a block" do
      let(:spy_under_test) { spy("spy") }

      before do
        test_visibility.trace("my step", type: "step") do |span|
          spy_under_test.call

          span&.set_metric("my.metric", 42)
        end
      end

      it "does not create spans" do
        expect(spans.count).to eq(0)
      end

      it "executes the test code" do
        expect(spy_under_test).to have_received(:call)
      end
    end

    context "without a block" do
      subject { test_visibility.trace("my step", type: "step") }

      it { is_expected.to be_nil }
    end
  end

  describe "#active_test_session" do
    subject { test_visibility.active_test_session }

    it { is_expected.to be_nil }
  end

  describe "#active_test_module" do
    subject { test_visibility.active_test_module }
    it { is_expected.to be_nil }
  end

  describe "#active_test" do
    subject { test_visibility.active_test }

    it { is_expected.to be_nil }
  end

  describe "#active_span" do
    subject { test_visibility.active_span }

    it { is_expected.to be_nil }
  end
end
