# frozen_string_literal: true

require "datadog/ci/event_span"
require "datadog/ci/event_trace"
require "datadog/ci/test_tracing/serializers/span"

RSpec.describe Datadog::CI::EventSpan do
  subject(:span) { described_class.new("test", trace_id: 123) }

  def serialized_content
    span.finish
    trace = Datadog::CI::EventTrace.new(span.trace_id, [span], runtime_id: "runtime")
    serializer = Datadog::CI::TestTracing::Serializers::Span.new(trace, span)
    MessagePack.unpack(MessagePack.pack(serializer)).fetch("content")
  end

  it "keeps numeric values for agent tags in string metadata" do
    %w[version http.status_code _dd.hostname].each do |key|
      span.set_tag(key, 123)
      expect(span.get_tag(key)).to eq("123")
      expect(span.metrics).not_to have_key(key)
    end
    span.set_tag("_dd.origin", 456)
    expect(span.meta["_dd.origin"]).to eq("456")
    expect(serialized_content.fetch("meta")).to include("version" => "123", "http.status_code" => "123")
  end

  it "preserves large integer tags as exact strings in the payload" do
    values = [-(1 << 64), -(1 << 53) - 1, (1 << 53) + 1, 1 << 80]
    values.each_with_index { |value, index| span.set_tag("id.#{index}", value) }
    content = serialized_content
    values.each_with_index do |value, index|
      expect(content.fetch("meta")["id.#{index}"]).to eq(value.to_s)
      expect(content.fetch("metrics")).not_to have_key("id.#{index}")
    end
  end

  it "keeps safe integer tags and other numeric values as serializable metrics" do
    span.set_tag("minimum", -(1 << 53))
    span.set_tag("maximum", 1 << 53)
    span.set_tag("ratio", Rational(1, 2))
    span.set_metric("numeric_string", "2.5")
    expect(serialized_content.fetch("metrics")).to include(
      "minimum" => -(1 << 53), "maximum" => 1 << 53,
      "ratio" => 0.5, "numeric_string" => 2.5
    )
  end

  it "repairs invalid encoding in tag keys, tag values, and metric keys" do
    key = "key\xFF".b
    span.set_tag(key, "value\xFF".b)
    span.set_metric("metric\xFF".b, 3)
    content = serialized_content
    expect(content.fetch("meta")).to include("key\uFFFD" => "value\uFFFD")
    expect(content.fetch("metrics")).to include("metric\uFFFD" => 3)
  end

  it "replaces metrics with string tags and serializes nil as an empty tag" do
    span.set_metric("custom", 7)
    span.set_tag("custom", nil)
    expect(span.meta).to include("custom" => "")
    expect(span.metrics).not_to have_key("custom")
    span.set_tag("custom", 9)
    expect(span.meta).not_to have_key("custom")
    expect(span.metrics).to include("custom" => 9)
  end

  it "ignores invalid metrics without poisoning other events" do
    [nil, "invalid", Float::NAN, Float::INFINITY, Complex(1, 2)].each do |value|
      span.set_metric("invalid", value)
    end
    span.set_tag("valid", "retained")
    expect(serialized_content.fetch("meta")).to include("valid" => "retained")
    expect(span.metrics).not_to have_key("invalid")
  end

  it "contains tag conversion errors and reports a warning" do
    value = Object.new
    allow(value).to receive(:to_s).and_raise(TypeError, "conversion failed")
    expect(Datadog::CI.logger).to receive(:warn).with(/Failed to set CI event tag: TypeError: conversion failed/)
    expect { span.set_tag("invalid", value) }.not_to raise_error
    expect(span.meta).not_to have_key("invalid")
  end

  it "contains failures from the logger while handling invalid metadata" do
    value = Object.new
    allow(value).to receive(:to_s).and_raise(TypeError, "conversion failed")
    allow(Datadog::CI.logger).to receive(:warn).and_raise(IOError, "logger failed")
    expect { span.set_tag("invalid", value) }.not_to raise_error
  end
end
