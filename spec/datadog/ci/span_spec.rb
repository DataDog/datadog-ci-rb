RSpec.describe Datadog::CI::Span do
  let(:tracer_span) { instance_double(Datadog::Tracing::SpanOperation, name: "span_name", type: "test") }
  subject(:span) { described_class.new(tracer_span) }

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

  describe "#clear_tag" do
    it "clears the tag" do
      expect(tracer_span).to receive(:clear_tag).with("foo")

      span.clear_tag("foo")
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
      expect(tracer_span).to receive(:set_tag).with("os.version", Datadog::Core::Environment::Platform.kernel_release)
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

  describe "#git_repository_url" do
    it "returns the git repository URL" do
      expect(tracer_span).to receive(:get_tag).with("git.repository_url").and_return("url")

      expect(span.git_repository_url).to eq("url")
    end
  end

  describe "#git_commit_sha" do
    it "returns the git commit SHA" do
      expect(tracer_span).to receive(:get_tag).with("git.commit.sha").and_return("sha")

      expect(span.git_commit_sha).to eq("sha")
    end
  end

  describe "#git_branch" do
    it "returns the git branch" do
      expect(tracer_span).to receive(:get_tag).with("git.branch").and_return("branch")

      expect(span.git_branch).to eq("branch")
    end
  end

  describe "#os_architecture" do
    it "returns the OS architecture" do
      expect(tracer_span).to receive(:get_tag).with("os.architecture").and_return("arch")

      expect(span.os_architecture).to eq("arch")
    end
  end

  describe "#os_platform" do
    it "returns the OS platform" do
      expect(tracer_span).to receive(:get_tag).with("os.platform").and_return("platform")

      expect(span.os_platform).to eq("platform")
    end
  end

  describe "#os_version" do
    it "returns the OS version" do
      expect(tracer_span).to receive(:get_tag).with("os.version").and_return("version")

      expect(span.os_version).to eq("version")
    end
  end

  describe "#runtime_name" do
    it "returns the runtime name" do
      expect(tracer_span).to receive(:get_tag).with("runtime.name").and_return("name")

      expect(span.runtime_name).to eq("name")
    end
  end

  describe "#runtime_version" do
    it "returns the runtime version" do
      expect(tracer_span).to receive(:get_tag).with("runtime.version").and_return("version")

      expect(span.runtime_version).to eq("version")
    end
  end
end
