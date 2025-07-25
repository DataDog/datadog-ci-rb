RSpec.describe Datadog::CI::Span do
  let(:tracer_span) { instance_double(Datadog::Tracing::SpanOperation, name: "span_name", type: "test") }
  subject(:span) { described_class.new(tracer_span) }

  describe "#name" do
    it "returns the span name" do
      expect(span.name).to eq("span_name")
    end
  end

  describe "#id" do
    it "returns the span ID" do
      expect(tracer_span).to receive(:id).and_return(123)
      expect(span.id).to eq(123)
    end
  end

  describe "#trace_id" do
    it "returns the trace ID" do
      expect(tracer_span).to receive(:trace_id).and_return(456)
      expect(span.trace_id).to eq(456)
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

  describe "#status" do
    context "when status is nil" do
      before do
        allow(tracer_span).to receive(:get_tag).with("test.status").and_return(nil)
      end

      it "returns nil" do
        expect(span.status).to be_nil
      end
    end

    context "when status is pass" do
      before do
        allow(tracer_span).to receive(:get_tag).with("test.status").and_return("pass")
      end

      it "returns pass" do
        expect(span.status).to eq("pass")
      end
    end

    context "when status is fail" do
      before do
        allow(tracer_span).to receive(:get_tag).with("test.status").and_return("fail")
      end

      it "returns fail" do
        expect(span.status).to eq("fail")
      end
    end

    context "when status is skip" do
      before do
        allow(tracer_span).to receive(:get_tag).with("test.status").and_return("skip")
      end

      it "returns skip" do
        expect(span.status).to eq("skip")
      end
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

  describe "#git_tag" do
    it "returns the git tag" do
      expect(tracer_span).to receive(:get_tag).with("git.tag").and_return("v1.0.0")

      expect(span.git_tag).to eq("v1.0.0")
    end

    it "returns nil if the tag is not set" do
      expect(tracer_span).to receive(:get_tag).with("git.tag").and_return(nil)

      expect(span.git_tag).to be_nil
    end
  end

  describe "#base_commit_sha" do
    it "returns the base commit SHA for the pull request" do
      expect(tracer_span).to receive(:get_tag).with("git.pull_request.base_branch_sha").and_return("base_sha")

      expect(span.base_commit_sha).to eq("base_sha")
    end

    it "returns nil if the tag is not set" do
      expect(tracer_span).to receive(:get_tag).with("git.pull_request.base_branch_sha").and_return(nil)

      expect(span.base_commit_sha).to be_nil
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

  describe "#original_git_commit_sha" do
    context "when head commit SHA is available" do
      it "returns the head commit SHA" do
        expect(span).to receive(:get_tag).with("git.commit.head.sha").and_return("head_sha")

        expect(span.original_git_commit_sha).to eq("head_sha")
      end
    end

    context "when head commit SHA is not available" do
      it "falls back to regular commit SHA" do
        expect(span).to receive(:get_tag).with("git.commit.head.sha").and_return(nil)
        expect(span).to receive(:git_commit_sha).and_return("regular_sha")

        expect(span.original_git_commit_sha).to eq("regular_sha")
      end
    end

    context "when both head and regular commit SHA are not available" do
      it "returns nil" do
        expect(span).to receive(:get_tag).with("git.commit.head.sha").and_return(nil)
        expect(span).to receive(:git_commit_sha).and_return(nil)

        expect(span.original_git_commit_sha).to be_nil
      end
    end
  end

  describe "#original_git_commit_message" do
    context "when head commit message is available" do
      it "returns the head commit message" do
        expect(span).to receive(:get_tag).with("git.commit.head.message").and_return("head_message")

        expect(span.original_git_commit_message).to eq("head_message")
      end
    end

    context "when head commit message is not available" do
      it "falls back to regular commit message" do
        expect(span).to receive(:get_tag).with("git.commit.head.message").and_return(nil)
        expect(span).to receive(:git_commit_message).and_return("regular_message")

        expect(span.original_git_commit_message).to eq("regular_message")
      end
    end

    context "when both head and regular commit message are not available" do
      it "returns nil" do
        expect(span).to receive(:get_tag).with("git.commit.head.message").and_return(nil)
        expect(span).to receive(:git_commit_message).and_return(nil)

        expect(span.original_git_commit_message).to be_nil
      end
    end
  end
end
