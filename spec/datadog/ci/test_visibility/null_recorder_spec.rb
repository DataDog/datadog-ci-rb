RSpec.describe Datadog::CI::TestVisibility::NullRecorder do
  let(:recorder) { described_class.new }

  describe "#start_test_session" do
    subject { recorder.start_test_session }

    it { is_expected.to be_nil }

    it "does not activate session" do
      expect(recorder.active_test_session).to be_nil
    end
  end

  describe "#start_test_module" do
    let(:module_name) { "my-module" }

    subject { recorder.start_test_module(module_name) }

    it { is_expected.to be_nil }

    it "does not activate module" do
      expect(recorder.active_test_module).to be_nil
    end
  end

  describe "#start_test_suite" do
    let(:suite_name) { "my-module" }

    subject { recorder.start_test_suite(suite_name) }

    it { is_expected.to be_nil }

    it "does not activate test suite" do
      expect(recorder.active_test_suite(suite_name)).to be_nil
    end
  end

  describe "#trace_test" do
    context "when given a block" do
      let(:spy_under_test) { spy("spy") }

      before do
        recorder.trace_test("my test", "my suite") do |test_span|
          spy_under_test.call

          test_span.passed! if test_span
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
      subject { recorder.trace_test("my test", "my suite") }

      it { is_expected.to be_nil }
    end
  end

  describe "#trace" do
    context "when given a block" do
      let(:spy_under_test) { spy("spy") }

      before do
        recorder.trace("step", "my step") do |span|
          spy_under_test.call

          span.set_metric("my.metric", 42) if span
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
      subject { recorder.trace("step", "my step") }

      it { is_expected.to be_nil }
    end
  end

  describe "#active_test_session" do
    subject { recorder.active_test_session }

    it { is_expected.to be_nil }
  end

  describe "#active_test_module" do
    subject { recorder.active_test_module }
    it { is_expected.to be_nil }
  end

  describe "#active_test" do
    subject { recorder.active_test }

    it { is_expected.to be_nil }
  end

  describe "#active_span" do
    subject { recorder.active_span }

    it { is_expected.to be_nil }
  end
end
