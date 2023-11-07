RSpec.describe Datadog::CI::Span do
  describe "#initialize" do
    let(:tracer_span) { instance_double(Datadog::Tracing::SpanOperation) }
    let(:span) { described_class.new(tracer_span, tags) }

    context "when tags are nil" do
      let(:tags) { nil }

      it "doesn't set any tags" do
        expect(tracer_span).to_not receive(:set_tag)
        span
      end
    end

    context "when tags are provided" do
      let(:tags) { {"foo" => "bar"} }

      it "sets provided tags along with default tag and environment tag" do
        # default tags
        expect(tracer_span).to receive(:set_tag).with("span.kind", "test")

        # runtime tags
        expect(tracer_span).to receive(:set_tag).with("os.architecture", ::RbConfig::CONFIG["host_cpu"])
        expect(tracer_span).to receive(:set_tag).with("os.platform", ::RbConfig::CONFIG["host_os"])
        expect(tracer_span).to receive(:set_tag).with("runtime.name", Datadog::Core::Environment::Ext::LANG_ENGINE)
        expect(tracer_span).to receive(:set_tag).with("runtime.version", Datadog::Core::Environment::Ext::ENGINE_VERSION)

        # client-supplied tags
        expect(tracer_span).to receive(:set_tag).with("foo", "bar")

        span
      end
    end
  end

  describe "#passed!" do
    let(:tracer_span) { instance_double(Datadog::Tracing::SpanOperation) }
    let(:span) { described_class.new(tracer_span) }

    it "sets the status to PASS" do
      expect(tracer_span).to receive(:set_tag).with("test.status", "pass")

      span.passed!
    end
  end

  describe "#failed!" do
    let(:tracer_span) { instance_double(Datadog::Tracing::SpanOperation) }
    let(:span) { described_class.new(tracer_span) }

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
    let(:tracer_span) { instance_double(Datadog::Tracing::SpanOperation) }
    let(:span) { described_class.new(tracer_span) }

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
    let(:tracer_span) { instance_double(Datadog::Tracing::SpanOperation) }
    let(:span) { described_class.new(tracer_span) }

    it "sets the tag" do
      expect(tracer_span).to receive(:set_tag).with("foo", "bar")

      span.set_tag("foo", "bar")
    end
  end

  describe "#set_metric" do
    let(:tracer_span) { instance_double(Datadog::Tracing::SpanOperation) }
    let(:span) { described_class.new(tracer_span) }

    it "sets the metric" do
      expect(tracer_span).to receive(:set_metric).with("foo", "bar")

      span.set_metric("foo", "bar")
    end
  end

  describe "#finish" do
    let(:tracer_span) { instance_double(Datadog::Tracing::SpanOperation) }
    let(:span) { described_class.new(tracer_span) }

    it "finishes the span" do
      expect(tracer_span).to receive(:finish)

      span.finish
    end
  end

  describe "#span_type" do
    let(:tracer_span) { instance_double(Datadog::Tracing::SpanOperation, type: "test") }
    let(:span) { described_class.new(tracer_span) }

    it "returns 'test'" do
      expect(span.span_type).to eq("test")
    end
  end
end
