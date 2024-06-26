require "datadog/ci"

# For contrib, we only allow one tracer to be active:
# the global tracer in +Datadog::Tracing+.
module TracerHelpers
  # traces a single test with given parameters
  # optionally adds a http span using `Datadog::Tracing.trace`
  def produce_test_trace(
    framework: "rspec",
    test_name: "test_add", test_suite: "calculator_tests",
    service: "rspec-test-suite", result: "PASSED", exception: nil,
    skip_reason: nil, with_http_span: false
  )
    Datadog::CI.trace_test(
      test_name,
      test_suite,
      tags: {
        Datadog::CI::Ext::Test::TAG_FRAMEWORK => framework,
        Datadog::CI::Ext::Test::TAG_FRAMEWORK_VERSION => "1.0.0"
      },
      service: service
    ) do |test|
      if with_http_span
        Datadog::Tracing.trace("http-call", type: "http", service: "net-http") do |span, trace|
          span.set_tag("custom_tag", "custom_tag_value")
          span.set_metric("custom_metric", 42)
        end
      end

      Datadog::CI.active_test&.set_tag("test_owner", "my_team")
      Datadog::CI.active_test&.set_metric("memory_allocations", 16)

      set_result(test, result: result, exception: exception, skip_reason: skip_reason) if test
    end
  end

  # traces a test session with given parameters and number of tests
  def produce_test_session_trace(
    tests_count: 1, framework: "rspec",
    test_name: "test_add", test_suite: "calculator_tests", test_module_name: "arithmetic",
    service: "rspec-test-suite", result: "PASSED", exception: nil,
    skip_reason: nil, with_http_span: false
  )
    test_session = Datadog::CI.start_test_session(
      service: service,
      tags: {
        Datadog::CI::Ext::Test::TAG_FRAMEWORK => framework,
        Datadog::CI::Ext::Test::TAG_FRAMEWORK_VERSION => "1.0.0"
      }
    )

    test_module = Datadog::CI.start_test_module(test_module_name)

    tracked_test_suite = Datadog::CI.start_test_suite(test_suite)

    tests_count.times do |num|
      produce_test_trace(
        framework: framework,
        test_name: "#{test_name}.run.#{num}", test_suite: test_suite,
        # service is inherited from test_session
        service: nil,
        result: result, exception: exception, skip_reason: skip_reason,
        with_http_span: with_http_span
      )
    end

    if tracked_test_suite
      set_result(tracked_test_suite, result: result, exception: exception, skip_reason: skip_reason)
      tracked_test_suite.finish
    end

    if test_module
      set_result(test_module, result: result, exception: exception, skip_reason: skip_reason)
      test_module.finish
    end

    if test_session
      set_result(test_session, result: result, exception: exception, skip_reason: skip_reason)
      test_session.finish
    end
  end

  # returns test session span and asserts that there must be no more than one
  def test_session_span
    @test_session_span ||= begin
      test_session_spans = spans.filter { |span| span.type == "test_session_end" }
      expect(test_session_spans.count).to be <= 1
      test_session_spans.first
    end
  end

  # returns test module span and asserts that there must be no more than one
  def test_module_span
    @test_module_span ||= begin
      test_module_spans = spans.filter { |span| span.type == "test_module_end" }
      expect(test_module_spans.count).to be <= 1
      test_module_spans.first
    end
  end

  # returns all test spans
  def test_spans
    @test_spans ||= spans.filter { |span| span.type == "test" }
  end

  # returns all test suite spans
  def test_suite_spans
    @test_suite_spans ||= spans.filter { |span| span.type == "test_suite_end" }
  end

  # returns all custom (i.e. not test/suite/module/session) spans
  def custom_spans
    @custom_spans ||= spans.filter do |span|
      !Datadog::CI::Ext::AppTypes::CI_SPAN_TYPES.include?(span.type)
    end
  end

  def first_test_span
    @first_span_span ||= test_spans.first
  end

  def first_test_suite_span
    @first_stest_suite_span ||= test_suite_spans.first
  end

  def first_custom_span
    @first_custom_span ||= custom_spans.first
  end

  # -------------------------------------
  # methods inherited from dd-trace-rb
  # -------------------------------------

  # Returns the current tracer instance
  def tracer
    Datadog::Tracing.send(:tracer)
  end

  # Returns traces and caches it (similar to +let(:traces)+).
  def traces
    @traces ||= fetch_traces
  end

  # Returns spans and caches it (similar to +let(:spans)+).
  def spans
    @spans ||= fetch_spans
  end

  # Returns the only trace in the current tracer writer.
  #
  # This method will not allow for ambiguous use,
  # meaning it will throw an error when more than
  # one span is available.
  def trace
    @trace ||= begin
      expect(traces).to have(1).item, "Requested the only trace, but #{traces.size} traces are available"
      traces.first
    end
  end

  # returns trace associated with given span
  def trace_for_span(span)
    traces.find { |trace| trace.id == span.trace_id }
  end

  # Returns the only span in the current tracer writer.
  #
  # This method will not allow for ambiguous use,
  # meaning it will throw an error when more than
  # one span is available.
  def span
    @span ||= begin
      expect(spans).to have(1).item, "Requested the only span, but #{spans.size} spans are available"
      spans.first
    end
  end

  # Retrieves all traces in the current tracer instance.
  # This method does not cache its results.
  def fetch_traces(tracer = self.tracer)
    tracer.instance_variable_get(:@traces) || []
  end

  # Retrieves and sorts all spans in the current tracer instance.
  # This method does not cache its results.
  def fetch_spans(tracer = self.tracer)
    traces = fetch_traces(tracer)
    traces.collect(&:spans).flatten.sort! do |a, b|
      if a.name == b.name
        if a.resource == b.resource
          if a.start_time == b.start_time
            a.end_time <=> b.end_time
          else
            a.start_time <=> b.start_time
          end
        else
          a.resource <=> b.resource
        end
      else
        a.name <=> b.name
      end
    end
  end

  def set_result(span, result: "PASSED", exception: nil, skip_reason: nil)
    case result
    when "FAILED"
      span.failed!(exception: exception)
    when "SKIPPED"
      span.skipped!(exception: exception, reason: skip_reason)
    else
      span.passed!
    end
  end

  # Remove all traces from the current tracer instance and
  # busts cache of +#spans+ and +#span+.
  def clear_traces!
    tracer.instance_variable_set(:@traces, [])

    @traces = nil
    @trace = nil
    @spans = nil
    @span = nil
  end

  RSpec.configure do |config|
    # Capture spans from the global tracer
    config.before do
      # DEV `*_any_instance_of` has concurrency issues when running with parallelism (e.g. JRuby).
      # DEV Single object `allow` and `expect` work as intended with parallelism.
      allow(Datadog::Tracing::Tracer).to receive(:new).and_wrap_original do |method, **args, &block|
        instance = method.call(**args, &block)

        # The mutex must be eagerly initialized to prevent race conditions on lazy initialization
        write_lock = Mutex.new
        allow(instance).to receive(:write) do |trace|
          instance.instance_exec do
            write_lock.synchronize do
              @traces ||= []
              @traces << trace
            end
          end
        end

        instance
      end
    end

    # Execute shutdown! after the test has finished
    # teardown and mock verifications.
    #
    # Changing this to `config.after(:each)` would
    # put shutdown! inside the test scope, interfering
    # with mock assertions.
    config.around do |example|
      example.run.tap do
        Datadog::Tracing.shutdown!
      end
    end
  end

  # Useful for integration testing.
  def use_real_tracer!
    @use_real_tracer = true
    allow(Datadog::Tracing::Tracer).to receive(:new).and_call_original
  end
end
