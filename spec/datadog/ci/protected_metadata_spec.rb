# frozen_string_literal: true

RSpec.describe "SDK-owned metadata" do
  include_context "CI mode activated"

  around do |example|
    ClimateControl.modify("DD_GIT_BRANCH" => "main", "GITLAB_CI" => "true", "CI_JOB_NAME" => "tests") { example.run }
  end

  it "reads shared metadata without storing it on test spans, including active wrappers" do
    test = Datadog::CI.start_test("example", "suite")
    expect(test.git_branch).to eq("main")
    wrapper = Datadog::CI::Span.new(test.tracer_span)
    expect(wrapper.git_branch).to eq("main")
    expect(wrapper.get_metric("git.branch")).to eq("main")
    expect(test_tracing.active_span.get_tag("git.branch")).to eq("main")
    expect(test.tracer_span.get_tag("git.branch")).to be_nil
    test.finish
    expect(spans.first.meta).not_to have_key("git.branch")
  end

  it "rejects setting, clearing and metric conversion of shared tags" do
    test = Datadog::CI.start_test("example", "suite")
    test.set_tag("git.branch", "other")
    test.clear_tag("git.branch")
    test.set_metric("git.branch", 42)
    test.set_tags("git.branch" => "other", "custom.tag" => "allowed")
    expect(test.git_branch).to eq("main")
    expect(test.get_tag("custom.tag")).to eq("allowed")
    expect(test.tracer_span.get_tag("git.branch")).to be_nil
    test.finish
  end

  it "rejects public changes to per-test fields but preserves supported operations" do
    test = Datadog::CI.start_test("example", "suite")
    test.passed!
    test.set_tag("test.status", "fail")
    test.clear_tag("test.name")
    test.set_metric("test.status", 123)
    expect(test.status).to eq("pass")
    expect(test.name).to eq("example")
    test.failed!
    expect(test.status).to eq("fail")
    test.set_parameters({"input" => "value"})
    expect(test.parameters).to include("value")
    test.finish
  end

  it "filters protected creation tags while keeping manual instrumentation inputs" do
    session = Datadog::CI.start_test_session(tags: {"test.framework" => "custom", "git.branch" => "other", "test.is_retry" => "true"})
    test = Datadog::CI.start_test("example", "suite", tags: {"test.name" => "wrong", "test.status" => "pass", "test.custom" => "value"})
    expect(session.get_tag("test.framework")).to eq("custom")
    expect(session.git_branch).to eq("main")
    expect(session.get_tag("test.is_retry")).to be_nil
    expect(test.name).to eq("example")
    expect(test.status).to be_nil
    expect(test.get_tag("test.custom")).to eq("value")
    test.finish
    session.finish
  end

  it "does not give unrelated application spans CI defaults" do
    test = Datadog::CI.start_test("example", "suite")
    Datadog::Tracing.trace("http.request", type: "http") do
      expect(Datadog::CI.active_span.get_tag("git.branch")).to be_nil
    end
    test.finish
  end
  it "protects every registered SDK tag, even when it has no value yet" do
    span = Datadog::CI::Span.new(Datadog::Tracing::SpanOperation.new("example"))
    Datadog::CI::Ext::Metadata::PROTECTED_TAGS.each do |key|
      span.set_tag(key, "injected")
      expect(span.get_tag(key)).to be_nil
      span.set_internal_tag(key, "sdk")
      span.clear_tag(key)
      span.set_tags(key => "injected")
      span.set_metric(key, 123)
      expect(span.get_tag(key)).to eq("sdk")
    end
    span.set_tag("test.custom", "allowed")
    span.clear_tag("test.custom")
    expect(span.get_tag("test.custom")).to be_nil
  end

  it "keeps the protection registry complete for SDK tag and metric constants" do
    namespaces = [Datadog::CI::Ext::Test, Datadog::CI::Ext::Git, Datadog::CI::Ext::Environment,
      Datadog::CI::Ext::Test::LibraryCapabilities, Datadog::CI::Ext::Test::LibraryConfigurationError]
    keys = namespaces.flat_map do |namespace|
      namespace.constants(false).select { |name| name.to_s.match?(/\A(TAG_|METRIC_)/) }.map { |name| namespace.const_get(name) }
    end
    expect(Datadog::CI::Ext::Metadata::PROTECTED_TAGS).to match_array(keys.uniq)
  end

  it "shares every SDK environment tag" do
    namespaces = [Datadog::CI::Ext::Git, Datadog::CI::Ext::Environment]
    keys = namespaces.flat_map do |namespace|
      namespace.constants(false).select { |name| name.to_s.start_with?("TAG_") }.map { |name| namespace.const_get(name) }
    end
    expect(Datadog::CI::Ext::Metadata::SHARED_ENVIRONMENT_TAGS).to match_array(keys.uniq)
  end

  it "preserves a snapshot when the environment changes and shares values between tests" do
    first = Datadog::CI.start_test("first", "suite")
    first.finish
    ClimateControl.modify("DD_GIT_BRANCH" => "other") do
      second = Datadog::CI.start_test("second", "suite")
      expect(second.git_branch).to equal(first.git_branch)
      expect(second.git_branch).to eq("main")
      expect(second.git_branch).to be_frozen
      second.finish
    end
  end

  it "does not attach environment metadata to ordinary CI custom spans" do
    test = Datadog::CI.start_test("example", "suite")
    Datadog::CI.trace("setup", tags: {"custom.tag" => "value"}) do |span|
      expect(span.git_branch).to be_nil
      expect(Datadog::CI.active_span.git_branch).to be_nil
      expect(span.os_architecture).to be_nil
      expect(span.runtime_version).to be_nil
      expect(span.get_metric(Datadog::CI::Ext::Test::METRIC_CPU_COUNT)).to be_nil
      expect(span.get_tag("custom.tag")).to eq("value")
    end
    test.finish
    custom_span = spans.find { |span| span.name == "setup" }
    expect(custom_span.meta.keys & test_tracing.shared_environment_tags.keys).to be_empty
  end

  it "looks up shared metadata on each read, even for wrappers created before initialization" do
    raw_span = Datadog::Tracing::SpanOperation.new("example", type: "test")
    wrapper = Datadog::CI::Span.new(raw_span)
    expect(wrapper.git_branch).to be_nil
    test = Datadog::CI.start_test("example", "suite")
    expect(wrapper.git_branch).to eq("main")
    expect(wrapper.get_metric("git.branch")).to eq("main")
    expect(raw_span.get_tag("git.branch")).to be_nil
    test.finish
  end

  it "logs a rejected operation once, without including the attempted value" do
    output = StringIO.new
    Datadog.configure { |c| c.logger.instance = Logger.new(output) }
    3.times do
      Datadog::CI.trace("setup", tags: {"git.commit.committer.date" => "sensitive-value"}) { |span| span.passed! }
    end
    expect(output.string.scan("Ignoring initial_tags for SDK-owned tag git.commit.committer.date").size).to eq(1)
    expect(output.string).not_to include("sensitive-value")
  end
end
