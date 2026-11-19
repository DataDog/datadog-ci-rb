# frozen_string_literal: true

require "open3"
require "json"

RSpec.describe "Application spans before the CI session" do
  def run_bootstrap(mode)
    script = File.expand_path("../../../support/bootstrap_trace_process.rb", __dir__)
    output, status = Open3.capture2e(RbConfig.ruby, "-Ilib", script, mode)
    expect(status.success?).to be(true), output
    JSON.parse(output.lines.last)
  end

  it "captures boot spans and imports direct legacy changes when the session starts" do
    result = run_bootstrap("direct_changes")

    expect(result.fetch("initial_spans")).to eq(["http.request"])
    expect(result.fetch("apm_paths")).to be_empty
    expect(result.fetch("session_service")).to eq("updated-service")
    expect(result.fetch("session_env")).to eq("updated-env")
    expect(result.fetch("session_tag")).to eq("updated-tag")
    expect(result.fetch("test_service")).to eq("updated-service")
    expect(result.fetch("replacement_keys")).to eq(["updated-key"])
    expect(result.fetch("boot_spans")).to contain_exactly(include("parent_id" => 0, "meta" => include("_dd.origin" => "")))
    expect(result.fetch("replacement_tests")).to contain_exactly(
      include("service" => "updated-service", "meta" => include("env" => "updated-env", "custom" => "updated-tag"))
    )
    expect(result.fetch("generation_replaced")).to be(true)
  end

  it "leaves disabled CI uninitialized and sends application spans to APM" do
    result = run_bootstrap("disabled")

    expect(result.fetch("initial_spans")).to be_empty
    expect(result.fetch("ci_initialized")).to be(false)
    expect(result.fetch("apm_paths")).to include("/v0.4/traces")
  end

  it "honors direct CI disablement after capturing a boot span" do
    result = run_bootstrap("disable_before_session")

    expect(result.fetch("initial_spans")).to eq(["http.request"])
    expect(result.fetch("session_started")).to be(false)
    expect(result.fetch("apm_paths")).to include("/v0.4/traces")
  end

  it "returns application delivery to APM after CI shutdown" do
    result = run_bootstrap("shutdown")

    expect(result.fetch("initial_spans")).to eq(["http.request"])
    expect(result.fetch("apm_paths")).to include("/v0.4/traces")
    expect(result.fetch("generation_replaced")).to be(false)
  end

  it "captures boot spans across application tracer reset and reconfiguration" do
    result = run_bootstrap("reconfigure")

    expect(result.fetch("initial_spans")).to eq(["http.request", "http.request"])
    expect(result.fetch("apm_paths")).to be_empty
    expect(result.fetch("session_service")).to eq("reconfigured-service")
  end
end
