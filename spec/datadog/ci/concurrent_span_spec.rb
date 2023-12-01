RSpec.describe Datadog::CI::ConcurrentSpan do
  describe "#finish" do
    include_context "Concurrency test"

    it "calls SpanOperation#stop once" do
      repeat do
        tracer_span = Datadog::Tracing::SpanOperation.new("operation")
        ci_span = described_class.new(tracer_span)

        expect(tracer_span).to receive(:stop).once

        run_concurrently do
          ci_span.finish
        end
      end
    end
  end

  # the following tests make sure that ConcurrentSpan works exactly like Span
  let(:tracer_span) { instance_double(Datadog::Tracing::SpanOperation, name: "span_name", type: "test") }
  subject(:span) { described_class.new(tracer_span) }

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
end
