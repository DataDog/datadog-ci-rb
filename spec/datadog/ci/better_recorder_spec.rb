RSpec.describe Datadog::CI::Recorder do
  subject(:recorder) { described_class.new }
  shared_examples_for "trace with ciapp-test origin" do
    let(:trace_under_test) { subject }

    it "trace origin is ciapp-test" do
      expect(trace_under_test.origin).to eq(Datadog::CI::Ext::Test::CONTEXT_ORIGIN)
    end
  end

  shared_examples_for "span with environment tags" do
    let(:environment_tags) { Datadog::CI::Ext::Environment.tags(ENV) }
    let(:span_under_test) { subject }

    it "has all the environment tags" do
      environment_tags.each do |key, value|
        expect(span_under_test.get_tag(key)).to eq(value)
      end
    end
  end

  shared_examples_for "span with default tags" do
    let(:span_under_test) { subject }

    it "span.kind is equal to test" do
      expect(span_under_test.get_tag(Datadog::CI::Ext::Test::TAG_SPAN_KIND)).to eq(Datadog::CI::Ext::AppTypes::TYPE_TEST)
    end
  end

  shared_examples_for "span with runtime tags" do
    let(:span_under_test) { subject }

    it "runtime tags are all set" do
      [
        Datadog::CI::Ext::Test::TAG_OS_ARCHITECTURE,
        Datadog::CI::Ext::Test::TAG_OS_PLATFORM,
        Datadog::CI::Ext::Test::TAG_RUNTIME_NAME,
        Datadog::CI::Ext::Test::TAG_RUNTIME_VERSION
      ].each do |tag|
        expect(span_under_test.get_tag(tag)).not_to be_nil
      end
      expect(span_under_test.get_tag(Datadog::CI::Ext::Test::TAG_COMMAND)).to eq(test_command)
    end
  end

  context "when test suite level visibility is disabled" do
    include_context "CI mode activated" do
      let(:experimental_test_suite_level_visibility_enabled) { false }
    end
  end

  context "when test suite level visibility is enabled" do
    include_context "CI mode activated"

    describe "#trace" do
      let(:span_type) { "step" }
      let(:span_name) { "my test step" }
      let(:tags) { {"test.framework" => "my-framework", "my.tag" => "my_value"} }

      context "when given a block" do
        before do
          recorder.trace(span_type, span_name, tags: tags) do |span|
            # simulate some work
            span.set_metric("my.metric", 42)
            sleep(0.1)
          end
        end
        subject { span }

        it "traces the block" do
          expect(subject.resource).to eq(span_name)
          expect(subject.span_type).to eq(span_type)
        end

        it "sets the custom metric correctly" do
          expect(subject.get_metric("my.metric")).to eq(42)
        end

        it "sets the tags correctly" do
          expect(subject.get_tag("test.framework")).to eq("my-framework")
          expect(subject.get_tag("my.tag")).to eq("my_value")
        end

        it_behaves_like "span with environment tags"
        it_behaves_like "span with default tags"
        it_behaves_like "span with runtime tags"
      end

      context "without a block" do
        subject { recorder.trace("step", "my test step", tags: tags) }

        it "returns a new CI span" do
          expect(subject).to be_kind_of(Datadog::CI::Span)
        end

        it "sets the tags correctly" do
          expect(subject.get_tag("test.framework")).to eq("my-framework")
          expect(subject.get_tag("my.tag")).to eq("my_value")
        end

        it "sets correct resource and span type for the underlying tracer span" do
          subject.finish

          expect(span.resource).to eq(span_name)
          expect(span.span_type).to eq(span_type)
        end

        it_behaves_like "span with environment tags"
        it_behaves_like "span with default tags"
        it_behaves_like "span with runtime tags"
      end
    end

    describe "#trace_test" do
      let(:test_name) { "my test" }
      let(:test_service_name) { "my-service" }
      let(:operation_name) { "my-operation" }
      let(:tags) { {"test.framework" => "my-framework", "my.tag" => "my_value"} }

      context "without a block" do
        subject do
          recorder.trace_test(test_name, service_name: test_service_name, operation_name: operation_name, tags: tags)
        end

        context "when there is no active test session" do
          it "returns a new CI test span" do
            expect(subject).to be_kind_of(Datadog::CI::Test)
            expect(subject.name).to eq(test_name)
            expect(subject.service).to eq(test_service_name)
            expect(subject.tracer_span.name).to eq(operation_name)
            expect(subject.span_type).to eq(Datadog::CI::Ext::AppTypes::TYPE_TEST)
          end

          it "sets the provided tags correctly" do
            expect(subject.get_tag("test.framework")).to eq("my-framework")
            expect(subject.get_tag("my.tag")).to eq("my_value")
          end

          it "does not connect the test span to the test session" do
            expect(subject.get_tag(Datadog::CI::Ext::Test::TAG_TEST_SESSION_ID)).to be_nil
          end

          it_behaves_like "span with environment tags"
          it_behaves_like "span with default tags"
          it_behaves_like "span with runtime tags"
        end

        context "when there is an active test session" do
          let(:test_session_tags) { {"test.framework_version" => "1.0", "my.session.tag" => "my_session_value"} }
          let(:session_service_name) { "my-session-service" }
          let(:test_service_name) { nil }

          let(:test_session) { recorder.start_test_session(service_name: session_service_name, tags: test_session_tags) }

          before do
            test_session
          end

          it "returns a new CI test span using service from the test session" do
            expect(subject).to be_kind_of(Datadog::CI::Test)
            expect(subject.name).to eq(test_name)
            expect(subject.service).to eq(session_service_name)
          end

          it "sets the provided tags correctly while inheriting some tags from the session" do
            expect(subject.get_tag("test.framework")).to eq("my-framework")
            expect(subject.get_tag("test.framework_version")).to eq("1.0")
            expect(subject.get_tag("my.tag")).to eq("my_value")
            expect(subject.get_tag("my.session.tag")).to be_nil
          end

          it "connects the test span to the test session" do
            expect(subject.get_tag(Datadog::CI::Ext::Test::TAG_TEST_SESSION_ID)).to eq(test_session.id.to_s)
          end

          it "starts a new trace" do
            expect(subject.tracer_span.trace_id).not_to eq(test_session.tracer_span.trace_id)
          end

          it_behaves_like "span with environment tags"
          it_behaves_like "span with default tags"
          it_behaves_like "span with runtime tags"
        end
      end

      context "when given a block" do
        before do
          recorder.trace_test(
            test_name,
            service_name: test_service_name,
            operation_name: operation_name,
            tags: tags
          ) do |test_span|
            # simulate some work
            test_span.set_metric("my.metric", 42)
            sleep(0.1)
          end
        end
        subject { span }

        it "traces and finishes a test" do
          expect(subject.get_tag(Datadog::CI::Ext::Test::TAG_NAME)).to eq(test_name)
          expect(subject.service).to eq(test_service_name)
          expect(subject.name).to eq(operation_name)
          expect(subject.span_type).to eq(Datadog::CI::Ext::AppTypes::TYPE_TEST)
        end

        it "sets the provided tags correctly" do
          expect(subject.get_tag("test.framework")).to eq("my-framework")
          expect(subject.get_tag("my.tag")).to eq("my_value")
        end

        it_behaves_like "span with environment tags"
        it_behaves_like "span with default tags"
        it_behaves_like "span with runtime tags"
      end
    end
  end
end
