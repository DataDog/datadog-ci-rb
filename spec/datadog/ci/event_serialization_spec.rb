# frozen_string_literal: true

require "spec_helper"
require "datadog/ci/event_span"
require "datadog/ci/event_trace"
require "datadog/ci/test_tracing/serializers/span"

RSpec.describe "Independent CI event serialization" do
  it "serializes a completed CI event using the existing intake schema" do
    span = Datadog::CI::EventSpan.new("http.request", trace_id: 42, parent_id: 21, service: "tests", type: "http")
    span.set_tag("http.method", "GET")
    span.finish
    trace = Datadog::CI::EventTrace.new(42, [span], runtime_id: "runtime")
    serializer = Datadog::CI::TestTracing::Serializers::Span.new(trace, span)
    expect(serializer.valid?).to be(true)
    encoded = Datadog::CI::Utils::Encoding::MsgpackEncoder.encode(serializer)
    expect(encoded).to be_a(String)
    event = MessagePack.unpack(encoded)
    expect(event["type"]).to eq("span")
    expect(event["content"]).to include("trace_id" => 42, "parent_id" => 21, "name" => "http.request")
    expect(event["content"]["meta"]).to include("_dd.origin" => "ciapp-test", "http.method" => "GET")
  end

  it "rejects unfinished events without raising" do
    span = Datadog::CI::EventSpan.new("unfinished", trace_id: 42, service: "tests")
    trace = Datadog::CI::EventTrace.new(42, [span], runtime_id: "runtime")
    serializer = Datadog::CI::TestTracing::Serializers::Span.new(trace, span)
    expect(serializer.valid?).to be(false)
    expect(serializer.validation_errors).to have_key("duration")
  end

  it "normalizes external trace IDs without changing application metadata" do
    trace_id = (123 << 64) | 42
    span = Datadog::CI::EventSpan.new("external", trace_id: trace_id, service: "app")
    span.finish
    trace = Datadog::CI::EventTrace.new(trace_id, [span], runtime_id: "runtime")
    serializer = Datadog::CI::TestTracing::Serializers::Span.new(trace, span)
    expect(serializer.trace_id).to eq(42)
    expect(serializer.meta).to include("_dd.p.tid" => "000000000000007b", "_dd.origin" => "ciapp-test")
    expect(span.meta).to eq({})
  end
end
