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

  it "accepts non-shared SDK-owned creation tags through the manual API" do
    session = Datadog::CI.start_test_session(tags: {"test.framework" => "custom", "git.branch" => "other", "test.is_retry" => "true"})
    test = Datadog::CI.start_test("example", "suite", tags: {"test.name" => "wrong", "test.status" => "pass", "test.custom" => "value"})
    expect(session.get_tag("test.framework")).to eq("custom")
    expect(session.git_branch).to eq("main")
    expect(session.get_tag("test.is_retry")).to eq("true")
    expect(test.name).to eq("example")
    expect(test.status).to eq("pass")
    expect(test.get_tag("test.custom")).to eq("value")
    expect(session.get_metric("git.branch")).to eq("main")
    expect(test_tracing.shared_tags["git.branch"]).to eq("main")
    test.finish
    test_module = Datadog::CI.start_test_module("module", tags: {"test.status" => "pass"})
    suite = Datadog::CI.start_test_suite("manual suite", tags: {"test.status" => "pass"})
    expect(test_module.status).to eq("pass")
    expect(suite.status).to eq("pass")
    Datadog::CI.trace_test("block example", "manual suite", tags: {"test.status" => "pass"}) do |span|
      expect(span.status).to eq("pass")
    end
    Datadog::CI.trace("custom", tags: {"test.status" => "pass"}) do |span|
      expect(span.status).to eq("pass")
    end
    suite.finish
    test_module.finish
    session.finish
  end

  it "ignores shared creation tags, including absent environment fields and symbol keys" do
    output = StringIO.new
    Datadog.configure { |c| c.logger.instance = Logger.new(output) }
    tags = Datadog::CI::Ext::Metadata::SHARED_TAGS.to_h { |key| [key.to_sym, "manual-value"] }
    test = Datadog::CI.start_test("example", "suite", tags: tags)
    expect(test.git_branch).to eq("main")
    Datadog::CI::Ext::Metadata::SHARED_TAGS.each do |key|
      expect(test.tracer_span.get_tag(key)).to be_nil
    end
    expect(test_tracing.shared_tags.values).not_to include("manual-value")
    expect(output.string).not_to include("Ignoring")
    test.finish
  end

  it "does not give unrelated application spans CI defaults" do
    test = Datadog::CI.start_test("example", "suite")
    Datadog::Tracing.trace("http.request", type: "http") do
      expect(Datadog::CI.active_span.get_tag("git.branch")).to be_nil
    end
    test.finish
  end
  it "protects every registered SDK tag and logs rejected writes once without their values" do
    output = StringIO.new
    Datadog.configure { |c| c.logger.instance = Logger.new(output) }
    span = Datadog::CI::Span.new(Datadog::Tracing::SpanOperation.new("example"))
    Datadog::CI::Ext::Metadata::PROTECTED_TAGS.each do |key|
      3.times { span.set_tag(key, "injected") }
      expect(span.get_tag(key)).to be_nil
      span.set_internal_tag(key, "sdk")
      span.clear_tag(key)
      span.set_tags(key => "injected")
      span.set_metric(key, 123)
      expect(span.get_tag(key)).to eq("sdk")
    end
    expect(output.string.scan("Ignoring set_tag for SDK-owned tag git.commit.committer.date").size).to eq(1)
    expect(output.string).not_to include("injected")
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
      session = Datadog::CI.start_test_session
      second = Datadog::CI.start_test("second", "suite")
      expect(second.git_branch).to equal(first.git_branch)
      expect(second.git_branch).to eq("main")
      expect(second.git_branch).to be_frozen
      second.finish
      session.finish
    end
  end

  it "does not attach shared environment metadata to ordinary CI custom spans" do
    test = Datadog::CI.start_test("example", "suite")
    Datadog::CI.trace("setup", tags: {"custom.tag" => "value"}) do |span|
      expect(span.git_branch).to be_nil
      expect(Datadog::CI.active_span.git_branch).to be_nil
      expect(span.get_tag("custom.tag")).to eq("value")
    end
    test.finish
    custom_span = spans.find { |span| span.name == "setup" }
    expect(custom_span.meta.keys & test_tracing.shared_tags.keys).to be_empty
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

  it "finalizes shared payload metadata when the session starts" do
    session = Datadog::CI.start_test_session
    metadata = test_tracing.shared_tags
    expect(metadata).to be_frozen
    expect(metadata).to include(
      "test_session.name" => session.name,
      "git.branch" => "main",
      "_dd.library_capabilities.auto_test_retries" => "1"
    )
    expect(metadata).to have_key("_dd.test.is_user_provided_service")
    test = Datadog::CI.start_test("example", "suite")
    metadata.each do |key, value|
      expect(value).to be_frozen
      expect(session.get_tag(key)).to eq(value)
      expect(test.get_tag(key)).to eq(value)
      expect(test.tracer_span.get_tag(key)).to be_nil
    end
    expect(test_tracing.shared_tags).to equal(metadata)
    test.finish
    session.finish
  end

  it "assembles shared payload metadata for manual tests without a session" do
    test = Datadog::CI.start_test("example", "suite")
    expect(test_tracing.shared_tags).to include("git.branch" => "main")
    expect(test_tracing.shared_tags).to include(Datadog::CI::Ext::Test::LibraryCapabilities::CAPABILITY_VERSIONS)
    test.finish
  end
end
