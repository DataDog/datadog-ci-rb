require_relative "../../../lib/ddcov/ddcov"

RSpec.describe Datadog::CI::Span do
  let(:tracer_span) { instance_double(Datadog::Tracing::SpanOperation, name: "span_name", type: "test") }
  subject(:span) { described_class.new(tracer_span) }

  describe "ddcov" do
    puts "----- Testing Object#my_fixed_args_method -----"

    "I am self".my_fixed_args_method("Hi from argument 1", "Hi from argument 2")

    puts
    puts "----- Testing Object#my_var_args_c_array_method -----"

    "Hi from self".my_var_args_c_array_method("1", "2", "3", "4")

    puts
    puts "----- Testing Object#my_var_args_rb_array_method -----"

    "Hi from self".my_var_args_rb_array_method("1", "2")

    puts
    puts "----- Testing Object#my_method_with_required_block -----"

    my_method_with_required_block do
      "foo"
    end

    puts "---- Test Array#puts_every_other ----"

    [1, 2, 3, 4, 5, 6, 7].puts_every_other
  end

  describe "#name" do
    it "returns the span name" do
      expect(span.name).to eq("span_name")
    end
  end

  describe "#passed?" do
    context "when status is PASS" do
      before do
        allow(tracer_span).to receive(:get_tag).with("test.status").and_return("pass")
      end

      it { is_expected.to be_passed }
    end

    context "when status is not PASS" do
      before do
        allow(tracer_span).to receive(:get_tag).with("test.status").and_return("fail")
      end

      it { is_expected.not_to be_passed }
    end
  end

  describe "#failed?" do
    context "when status is FAIL" do
      before do
        allow(tracer_span).to receive(:get_tag).with("test.status").and_return("fail")
      end

      it { is_expected.to be_failed }
    end

    context "when status is not FAIL" do
      before do
        allow(tracer_span).to receive(:get_tag).with("test.status").and_return("pass")
      end

      it { is_expected.not_to be_failed }
    end
  end

  describe "#skipped?" do
    context "when status is SKIP" do
      before do
        allow(tracer_span).to receive(:get_tag).with("test.status").and_return("skip")
      end

      it { is_expected.to be_skipped }
    end

    context "when status is not SKIP" do
      before do
        allow(tracer_span).to receive(:get_tag).with("test.status").and_return("pass")
      end

      it { is_expected.not_to be_skipped }
    end
  end

  describe "#undefined?" do
    context "when status is nil" do
      before do
        allow(tracer_span).to receive(:get_tag).with("test.status").and_return(nil)
      end

      it { is_expected.to be_undefined }
    end

    context "when status is not nil" do
      before do
        allow(tracer_span).to receive(:get_tag).with("test.status").and_return("pass")
      end

      it { is_expected.not_to be_undefined }
    end
  end

  describe "#passed!" do
    it "sets the status to PASS" do
      expect(tracer_span).to receive(:set_tag).with("test.status", "pass")

      span.passed!
    end
  end

  describe "#failed!" do
    context "when exception is nil" do
      it "sets the status to FAIL" do
        expect(tracer_span).to receive(:status=).with(1)
        expect(tracer_span).to receive(:set_tag).with("test.status", "fail")

        span.failed!
      end
    end

    context "when exception is provided" do
      it "sets the status to FAIL" do
        expect(tracer_span).to receive(:status=).with(1)
        expect(tracer_span).to receive(:set_tag).with("test.status", "fail")
        expect(tracer_span).to receive(:set_error).with("error")

        span.failed!(exception: "error")
      end
    end
  end

  describe "#skipped!" do
    context "when exception is nil" do
      it "sets the status to SKIP" do
        expect(tracer_span).to receive(:set_tag).with("test.status", "skip")
        expect(tracer_span).not_to receive(:set_error)

        span.skipped!
      end
    end

    context "when exception is provided" do
      it "sets the status to SKIP and sets error" do
        expect(tracer_span).to receive(:set_tag).with("test.status", "skip")
        expect(tracer_span).to receive(:set_error).with("error")

        span.skipped!(exception: "error")
      end
    end

    context "when reason is nil" do
      it "doesn't set the skip reason tag" do
        expect(tracer_span).to receive(:set_tag).with("test.status", "skip")
        expect(tracer_span).not_to receive(:set_tag).with("test.skip_reason", "reason")

        span

        span.skipped!
      end
    end

    context "when reason is provided" do
      it "sets the skip reason tag" do
        expect(tracer_span).to receive(:set_tag).with("test.status", "skip")
        expect(tracer_span).to receive(:set_tag).with("test.skip_reason", "reason")

        span.skipped!(reason: "reason")
      end
    end
  end

  describe "#set_tag" do
    it "sets the tag" do
      expect(tracer_span).to receive(:set_tag).with("foo", "bar")

      span.set_tag("foo", "bar")
    end
  end

  describe "#set_tags" do
    it "sets the tags" do
      expect(tracer_span).to receive(:set_tags).with({"foo" => "bar", "baz" => "qux"})

      span.set_tags("foo" => "bar", "baz" => "qux")
    end
  end

  describe "#set_metric" do
    it "sets the metric" do
      expect(tracer_span).to receive(:set_metric).with("foo", "bar")

      span.set_metric("foo", "bar")
    end
  end

  describe "#set_default_tags" do
    it "sets the default tags" do
      expect(tracer_span).to receive(:set_tag).with("span.kind", "test")

      span.set_default_tags
    end
  end

  describe "#set_environment_runtime_tags" do
    let(:test_command) { "command" }

    before do
      allow(Datadog::CI::Utils::TestRun).to receive(:command).and_return(test_command)
    end

    it "sets the environment runtime tags" do
      expect(tracer_span).to receive(:set_tag).with("os.architecture", ::RbConfig::CONFIG["host_cpu"])
      expect(tracer_span).to receive(:set_tag).with("os.platform", ::RbConfig::CONFIG["host_os"])
      expect(tracer_span).to receive(:set_tag).with("runtime.name", Datadog::Core::Environment::Ext::LANG_ENGINE)
      expect(tracer_span).to receive(:set_tag).with("runtime.version", Datadog::Core::Environment::Ext::ENGINE_VERSION)
      expect(tracer_span).to receive(:set_tag).with("test.command", test_command)

      span.set_environment_runtime_tags
    end
  end

  describe "#finish" do
    it "finishes the span" do
      expect(tracer_span).to receive(:finish)

      span.finish
    end
  end

  describe "#type" do
    it "returns 'test'" do
      expect(span.type).to eq("test")
    end
  end
end
