RSpec.describe Datadog::CI::Recorder do
  let(:trace_op) { instance_double(Datadog::Tracing::TraceOperation) }
  let(:service) { "service" }
  let(:operation_name) { "span name" }

  before do
    allow(Datadog::Tracing).to receive(:active_trace).and_return(trace_op)
    allow(trace_op).to receive(:origin=)
  end

  shared_examples_for "internal tracing context" do
    it do
      expect(Datadog::Tracing::Contrib::Analytics)
        .to have_received(:set_measured)
        .with(span_op)
    end

    # TODO: move to Span
    # it do
    #   expect(span_op.get_tag(Datadog::CI::Ext::Test::TAG_SPAN_KIND))
    #     .to eq(Datadog::CI::Ext::AppTypes::TYPE_TEST)
    # end

    # it do
    #   Datadog::CI::Ext::Environment.tags(ENV).each do |key, value|
    #     expect(span_op.get_tag(key))
    #       .to eq(value)
    #   end
    # end

    it do
      expect(trace_op)
        .to have_received(:origin=)
        .with(Datadog::CI::Ext::Test::CONTEXT_ORIGIN)
    end
  end

  describe "::trace_test" do
    let(:tags) { {} }
    let(:test_name) { "test name" }

    let(:expected_tags) do
      tags
        .merge(Datadog::CI::Ext::Environment.tags(ENV))
        .merge({Datadog::CI::Ext::Test::TAG_NAME => test_name})
    end

    context "when given a block" do
      subject(:trace) do
        described_class.trace_test(
          test_name,
          service_name: service,
          operation_name: operation_name,
          tags: tags,
          &block
        )
      end

      let(:span_op) { Datadog::Tracing::SpanOperation.new(operation_name) }
      let(:ci_test) { instance_double(Datadog::CI::Span) }
      let(:block) { proc { |s| block_spy.call(s) } }
      let(:block_result) { double("result") }
      let(:block_spy) { spy("block") }

      before do
        allow(block_spy).to receive(:call).and_return(block_result)

        allow(Datadog::Tracing)
          .to receive(:trace) do |trace_span_name, trace_span_options, &trace_block|
            expect(trace_span_name).to be(operation_name)
            expect(trace_span_options).to eq(
              {
                span_type: Datadog::CI::Ext::AppTypes::TYPE_TEST,
                resource: test_name,
                service: service
              }
            )
            trace_block.call(span_op, trace_op)
          end

        allow(Datadog::Tracing::Contrib::Analytics).to receive(:set_measured)
        allow(Datadog::CI::Span).to receive(:new).with(span_op, expected_tags).and_return(ci_test)

        trace
      end

      it_behaves_like "internal tracing context"
      it { expect(block_spy).to have_received(:call).with(ci_test) }
      it { is_expected.to be(block_result) }
    end

    context "when not given a block" do
      subject(:trace) do
        described_class.trace_test(
          test_name,
          service_name: service,
          operation_name: operation_name,
          tags: tags
        )
      end
      let(:span_op) { Datadog::Tracing::SpanOperation.new(operation_name) }
      let(:ci_test) { instance_double(Datadog::CI::Span) }

      before do
        allow(Datadog::Tracing)
          .to receive(:trace)
          .with(
            operation_name,
            {
              span_type: Datadog::CI::Ext::AppTypes::TYPE_TEST,
              resource: test_name,
              service: service
            }
          )
          .and_return(span_op)

        allow(Datadog::Tracing::Contrib::Analytics).to receive(:set_measured)
        allow(Datadog::CI::Span).to receive(:new).with(span_op, expected_tags).and_return(ci_test)

        trace
      end

      it_behaves_like "internal tracing context"
      it { is_expected.to be(ci_test) }
    end
  end

  # TODO: move to span
  # describe "::set_tags!" do
  #   subject(:set_tags!) { described_class.set_tags!(trace_op, span_op, tags) }
  #   let(:span_op) { Datadog::Tracing::SpanOperation.new(operation_name) }
  #   let(:tags) { {} }

  #   before do
  #     allow(Datadog::Tracing::Contrib::Analytics).to receive(:set_measured)
  #   end

  #   it_behaves_like "default test span operation tags" do
  #     before { set_tags! }
  #   end

  #   context "when trace operation is given" do
  #     before { set_tags! }

  #     it do
  #       expect(trace_op)
  #         .to have_received(:origin=)
  #         .with(Datadog::CI::Ext::Test::CONTEXT_ORIGIN)
  #     end
  #   end

  #   context "when :framework is given" do
  #     let(:tags) { {framework: framework} }
  #     let(:framework) { "framework" }

  #     before { set_tags! }

  #     it do
  #       expect(span_op.get_tag(Datadog::CI::Ext::Test::TAG_FRAMEWORK))
  #         .to eq(framework)
  #     end
  #   end

  #   context "when :framework_version is given" do
  #     let(:tags) { {framework_version: framework_version} }
  #     let(:framework_version) { "framework_version" }

  #     before { set_tags! }

  #     it do
  #       expect(span_op.get_tag(Datadog::CI::Ext::Test::TAG_FRAMEWORK_VERSION))
  #         .to eq(framework_version)
  #     end
  #   end

  #   context "when :test_name is given" do
  #     let(:tags) { {test_name: test_name} }
  #     let(:test_name) { "test name" }

  #     before { set_tags! }

  #     it do
  #       expect(span_op.get_tag(Datadog::CI::Ext::Test::TAG_NAME))
  #         .to eq(test_name)
  #     end
  #   end

  #   context "when :test_suite is given" do
  #     let(:tags) { {test_suite: test_suite} }
  #     let(:test_suite) { "test suite" }

  #     before { set_tags! }

  #     it do
  #       expect(span_op.get_tag(Datadog::CI::Ext::Test::TAG_SUITE))
  #         .to eq(test_suite)
  #     end
  #   end

  #   context "when :test_type is given" do
  #     let(:tags) { {test_type: test_type} }
  #     let(:test_type) { "test type" }

  #     before { set_tags! }

  #     it do
  #       expect(span_op.get_tag(Datadog::CI::Ext::Test::TAG_TYPE))
  #         .to eq(test_type)
  #     end
  #   end

  #   context "with environment runtime information" do
  #     context "for the architecture platform" do
  #       subject(:tag) do
  #         set_tags!
  #         span_op.get_tag(Datadog::CI::Ext::Test::TAG_OS_ARCHITECTURE)
  #       end

  #       it { is_expected.to eq("x86_64").or eq("i686").or eq("aarch64").or start_with("arm") }
  #     end

  #     context "for the OS platform" do
  #       subject(:tag) do
  #         set_tags!
  #         span_op.get_tag(Datadog::CI::Ext::Test::TAG_OS_PLATFORM)
  #       end

  #       context "with Linux", if: PlatformHelpers.linux? do
  #         it { is_expected.to start_with("linux") }
  #       end

  #       context "with Mac OS", if: PlatformHelpers.mac? do
  #         it { is_expected.to start_with("darwin") }
  #       end

  #       it "returns a valid string" do
  #         is_expected.to be_a(String)
  #       end
  #     end

  #     context "for the runtime name" do
  #       subject(:tag) do
  #         set_tags!
  #         span_op.get_tag(Datadog::CI::Ext::Test::TAG_RUNTIME_NAME)
  #       end

  #       context "with MRI", if: PlatformHelpers.mri? do
  #         it { is_expected.to eq("ruby") }
  #       end

  #       context "with JRuby", if: PlatformHelpers.jruby? do
  #         it { is_expected.to eq("jruby") }
  #       end

  #       context "with TruffleRuby", if: PlatformHelpers.truffleruby? do
  #         it { is_expected.to eq("truffleruby") }
  #       end

  #       it "returns a valid string" do
  #         is_expected.to be_a(String)
  #       end
  #     end

  #     context "for the runtime version" do
  #       subject(:tag) do
  #         set_tags!
  #         span_op.get_tag(Datadog::CI::Ext::Test::TAG_RUNTIME_VERSION)
  #       end

  #       context "with MRI", if: PlatformHelpers.mri? do
  #         it { is_expected.to match(/^[23]\./) }
  #       end

  #       context "with JRuby", if: PlatformHelpers.jruby? do
  #         it { is_expected.to match(/^9\./) }
  #       end

  #       context "with TruffleRuby", if: PlatformHelpers.truffleruby? do
  #         it { is_expected.to match(/^2\d\./) }
  #       end

  #       it "returns a valid string" do
  #         is_expected.to be_a(String)
  #       end
  #     end
  #   end
  # end

  # TODO: move to Span
  # describe "::passed!" do
  #   subject(:passed!) { described_class.passed!(span_op) }
  #   let(:span_op) { instance_double(Datadog::Tracing::SpanOperation) }

  #   before do
  #     allow(span_op).to receive(:set_tag)
  #     passed!
  #   end

  #   it do
  #     expect(span_op)
  #       .to have_received(:set_tag)
  #       .with(
  #         Datadog::CI::Ext::Test::TAG_STATUS,
  #         Datadog::CI::Ext::Test::Status::PASS
  #       )
  #   end
  # end

  # TODO: move to Span
  # describe "::failed!" do
  #   let(:span_op) { instance_double(Datadog::Tracing::SpanOperation) }

  #   before do
  #     allow(span_op).to receive(:status=)
  #     allow(span_op).to receive(:set_tag)
  #     allow(span_op).to receive(:set_error)
  #     failed!
  #   end

  #   shared_examples "failed test span operation" do
  #     it do
  #       expect(span_op)
  #         .to have_received(:status=)
  #         .with(1)
  #     end

  #     it do
  #       expect(span_op)
  #         .to have_received(:set_tag)
  #         .with(
  #           Datadog::CI::Ext::Test::TAG_STATUS,
  #           Datadog::CI::Ext::Test::Status::FAIL
  #         )
  #     end
  #   end

  #   context "when no exception is given" do
  #     subject(:failed!) { described_class.failed!(span_op) }

  #     it_behaves_like "failed test span operation"
  #     it { expect(span_op).to_not have_received(:set_error) }
  #   end

  #   context "when exception is given" do
  #     subject(:failed!) { described_class.failed!(span_op, exception) }
  #     let(:exception) { instance_double(StandardError) }

  #     it_behaves_like "failed test span operation"

  #     it do
  #       expect(span_op)
  #         .to have_received(:set_error)
  #         .with(exception)
  #     end
  #   end
  # end

  # TODO: move to Span
  # describe "::skipped!" do
  #   let(:span_op) { instance_double(Datadog::Tracing::SpanOperation) }

  #   before do
  #     allow(span_op).to receive(:set_tag)
  #     allow(span_op).to receive(:set_error)
  #     skipped!
  #   end

  #   shared_examples "skipped test span operation" do
  #     it do
  #       expect(span_op)
  #         .to have_received(:set_tag)
  #         .with(
  #           Datadog::CI::Ext::Test::TAG_STATUS,
  #           Datadog::CI::Ext::Test::Status::SKIP
  #         )
  #     end
  #   end

  #   context "when no exception is given" do
  #     subject(:skipped!) { described_class.skipped!(span_op) }

  #     it_behaves_like "skipped test span operation"
  #     it { expect(span_op).to_not have_received(:set_error) }
  #   end

  #   context "when exception is given" do
  #     subject(:skipped!) { described_class.skipped!(span_op, exception) }
  #     let(:exception) { instance_double(StandardError) }

  #     it_behaves_like "skipped test span operation"

  #     it do
  #       expect(span_op)
  #         .to have_received(:set_error)
  #         .with(exception)
  #     end
  #   end
  # end
end
