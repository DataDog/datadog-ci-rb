# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/test_impact_analysis/component"

RSpec.describe Datadog::CI::TestImpactAnalysis::Component, "execution ownership" do
  let(:root) { Datadog::CI::Git::LocalRepository.root }
  let(:paths) { %w[setup body child].map { |name| File.join(root, "adversarial_#{name}.rb") } }
  let(:sources) { paths.map { |path| RubyVM::InstructionSequence.compile("Thread.pass\n", path, path) } }
  let(:configuration) do
    double(:configuration, itr_enabled?: true, code_coverage_enabled?: true, tests_skipping_enabled?: false)
  end

  def configured_component(**options)
    component = described_class.new(dd_env: "test", enabled: true, **options)
    session = Datadog::CI::TestSession.new(Datadog::Tracing::SpanOperation.new("session"))
    component.configure(configuration, session)
    component
  end

  def test_with_context(name)
    test = Datadog::CI::Test.new(Datadog::Tracing::SpanOperation.new(name))
    test.context_ids = ["shared-context"]
    test
  end

  it "discards pending setup coverage when another thread enters the lifecycle" do
    expect_in_fork do
      component = configured_component
      code = sources
      component.on_test_context_started("shared-context")
      code[0].eval
      Thread.new { component.on_test_started(test_with_context("foreign")) }.value
      expect(component).not_to be_enabled
      expect(component).not_to be_code_coverage
      expect(component.on_test_finished(test_with_context("owner"), nil)).to be_nil
      expect(component.stop_coverage).to be_nil
    end
  end

  it "collects application threads and fibers even with the obsolete single-thread setting" do
    expect_in_fork do
      component = configured_component(use_single_threaded_coverage: true)
      code = sources
      component.start_coverage
      code[0].eval
      Thread.new { code[1].eval }.value
      Fiber.new { code[2].eval }.resume
      result = component.stop_coverage
      expect(result.keys).to include(*paths)
      expect(component).to be_enabled
    end
  end

  it "honors a replacement component's ignored path on the same fiber" do
    expect_in_fork do
      first = configured_component
      replacement = configured_component(bundle_location: root)
      code = sources
      first.start_coverage
      code[0].eval
      first.stop_coverage
      replacement.start_coverage
      code[1].eval
      expect(replacement.stop_coverage).to be_empty
    end
  end

  it "merges setup dependencies into every sequential test, including background work" do
    expect_in_fork do
      component = configured_component
      code = sources
      jobs, completed = Queue.new, Queue.new
      worker = Thread.new do
        while (job = jobs.pop)
          job.eval
          completed << true
        end
      end
      component.on_test_context_started("shared-context")
      jobs << code[0]
      completed.pop
      3.times do |index|
        test = test_with_context("test-#{index}")
        component.on_test_started(test)
        jobs << code[1]
        completed.pop
        event = component.on_test_finished(test, nil)
        expect(event.inspect_coverage.keys).to include(paths[0], paths[1])
        expect(event.inspect_coverage.keys).not_to include(paths[2])
      end
      component.clear_context_coverage("shared-context")
      jobs << nil
      worker.value
    end
  end

  it "stops pending context coverage even when the context has no tests" do
    expect_in_fork do
      component = configured_component
      code = sources
      component.on_test_context_started("empty")
      code[0].eval
      component.clear_context_coverage("empty")
      code[1].eval
      component.start_coverage
      code[2].eval
      result = component.stop_coverage
      expect(result.keys).to include(paths[2])
      expect(result.keys).not_to include(paths[0], paths[1])
    end
  end

  it "discards inherited collector data when a process worker starts collecting" do
    expect_in_fork do
      component = configured_component
      code = sources
      component.start_coverage
      code[0].eval
      expect_in_fork do
        component.start_coverage
        code[1].eval
        result = component.stop_coverage
        expect(result.keys).to include(paths[1])
        expect(result.keys).not_to include(paths[0])
      end
      result = component.stop_coverage
      expect(result.keys).to include(paths[0])
      expect(result.keys).not_to include(paths[1])
    end
  end
end
