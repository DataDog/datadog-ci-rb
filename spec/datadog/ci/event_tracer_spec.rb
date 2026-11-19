# frozen_string_literal: true

require "spec_helper"
require "open3"
require "rbconfig"
require "datadog/ci/event_tracer"

RSpec.describe Datadog::CI::EventTracer do
  let(:traces) { [] }
  let(:writer) { double(:writer) }
  let(:tracer) { described_class.new(writer: writer, service: "tests", tags: {"custom" => "value"}) }

  before do
    allow(writer).to receive(:write) { |trace| traces << trace }
  end

  it "loads the event runtime without the application tracer" do
    script = <<~RUBY
      require "datadog/ci/event_tracer"
      abort "application tracer loaded" if defined?(Datadog::Tracing)
    RUBY
    output, status = Open3.capture2e(RbConfig.ruby, "-Ilib", "-e", script)
    expect(status.success?).to be(true), output
  end

  it "links nested events and restores the previous context" do
    tracer.trace("test", new_trace: true) do |test|
      tracer.trace("step") do |step|
        expect(step.parent_id).to eq(test.id)
        expect(step.trace_id).to eq(test.trace_id)
        expect(step.service).to eq("tests")
        expect(tracer.active_span).to equal(step)
      end
      expect(tracer.active_span).to equal(test)
    end

    expect(tracer.active_span).to be_nil
    expect(traces.flat_map(&:spans).map(&:name)).to eq(%w[step test])
    expect(traces.map(&:origin).uniq).to eq(["ciapp-test"])
  end

  it "marks root events and service boundaries as top level" do
    tracer.trace("root") do |root|
      expect(root.get_metric("_dd.top_level")).to eq(1)
      tracer.trace("child") do |child|
        expect(child.get_metric("_dd.top_level")).to be_nil
      end
      tracer.trace("service", service: "other") do |other|
        expect(other.get_metric("_dd.top_level")).to eq(1)
      end
    end
  end

  it "starts each test in an independent trace" do
    tracer.trace("suite") do |suite|
      tracer.trace("test", new_trace: true) do |test|
        expect(test.parent_id).to eq(0)
        expect(test.trace_id).not_to eq(suite.trace_id)
      end
      expect(tracer.active_span).to equal(suite)
    end
  end

  it "records an application exception and re-raises the same exception" do
    failure = RuntimeError.new("application failure")
    expect do
      tracer.trace("test") { raise failure }
    end.to raise_error { |error| expect(error).to equal(failure) }

    span = traces.first.spans.first
    expect(span.status).to eq(1)
    expect(span.get_tag("error.type")).to eq("RuntimeError")
    expect(span.get_tag("error.message")).to eq("application failure")
    expect(span.duration).to be >= 0
    expect(tracer.active_span).to be_nil
  end

  it "finishes an event only once" do
    span = tracer.trace("test")
    2.times { span.finish }
    expect(traces.size).to eq(1)
  end

  it "keeps numeric metrics separate from string metadata" do
    span = tracer.trace("test")
    span.set_tag("count", 3)
    span.set_tag("flag", false)
    span.set_metric("invalid", Float::NAN)
    expect(span.metrics).to eq("_dd.top_level" => 1, "count" => 3)
    expect(span.meta).to include("flag" => "false", "custom" => "value")
    span.set_tag("count", "three")
    expect(span.get_metric("count")).to be_nil
    expect(span.get_tag("count")).to eq("three")
    span.finish
  end

  it "keeps event timing independent of later wall-clock stubs" do
    allow(Time).to receive(:now).and_return(Time.at(0))
    span = tracer.trace("test")
    span.finish
    expect(span.start_time.year).to be >= 2020
    expect(span.end_time).to be >= span.start_time
  end

  it "removes events finished by another thread from their original context" do
    span = tracer.trace("test")
    Thread.new { span.finish }.join
    expect(tracer.active_span).to be_nil
    expect(traces.size).to eq(1)
  end

  it "keeps concurrent test contexts separate" do
    ready = Queue.new
    finish = Queue.new
    thread = Thread.new do
      tracer.trace("worker") do |span|
        ready << span
        finish.pop
      end
    end
    worker_span = ready.pop
    tracer.trace("main") do |span|
      expect(span.trace_id).not_to eq(worker_span.trace_id)
      expect(tracer.active_span).to equal(span)
    end
    finish << true
    thread.join
    expect(traces.flat_map(&:spans).map(&:name)).to contain_exactly("main", "worker")
  end
end
