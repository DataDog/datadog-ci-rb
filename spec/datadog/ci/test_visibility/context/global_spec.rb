RSpec.describe Datadog::CI::TestVisibility::Context::Global do
  subject(:context) { described_class.new }

  let(:tracer_span) { double(Datadog::Tracing::SpanOperation, name: "test.session", service: "my-service") }
  let(:session) { Datadog::CI::TestSession.new(tracer_span) }
  let(:test_module) { Datadog::CI::TestModule.new(tracer_span) }

  describe "#service" do
    context "when a test session is active" do
      before do
        subject.fetch_or_activate_test_session { session }
      end

      it "returns the service name" do
        expect(subject.service).to eq("my-service")
      end
    end

    context "when no test session is active" do
      it "returns nil" do
        expect(subject.service).to be_nil
      end
    end
  end

  describe "#inheritable_session_tags" do
    context "when a test session is active" do
      let(:inheritable_tags) { {"my.session.tag" => "my.session.tag.value"} }
      before do
        expect(session).to receive(:inheritable_tags).and_return(inheritable_tags)

        subject.fetch_or_activate_test_session { session }
      end

      it "returns the inheritable session tags" do
        expect(subject.inheritable_session_tags).to eq(inheritable_tags)
      end
    end

    context "when no test session is active" do
      it "returns an empty hash" do
        expect(subject.inheritable_session_tags).to eq({})
      end
    end
  end

  describe "active_test_session" do
    context "when a test session is active" do
      before do
        subject.fetch_or_activate_test_session { session }
      end

      it "returns the active test session" do
        expect(subject.active_test_session).to be(session)
      end
    end

    context "when no test session is active" do
      it "returns nil" do
        expect(subject.active_test_session).to be_nil
      end
    end
  end

  describe "#deactivate_test_session!" do
    context "when a test session is active" do
      before do
        subject.fetch_or_activate_test_session { session }
      end

      it "deactivates the test session" do
        subject.deactivate_test_session!
        expect(subject.active_test_session).to be_nil
      end
    end

    context "when no test session is active" do
      it "does nothing" do
        subject.deactivate_test_session!
        expect(subject.active_test_session).to be_nil
      end
    end
  end

  describe "active_test_module" do
    context "when a test module is active" do
      before do
        subject.fetch_or_activate_test_module { test_module }
      end

      it "returns the active test module" do
        expect(subject.active_test_module).to be(test_module)
      end
    end

    context "when no test module is active" do
      it "returns nil" do
        expect(subject.active_test_module).to be_nil
      end
    end
  end

  describe "#deactivate_test_module!" do
    context "when a test module is active" do
      before do
        subject.fetch_or_activate_test_module { test_module }
      end

      it "deactivates the test module" do
        subject.deactivate_test_module!
        expect(subject.active_test_module).to be_nil
      end
    end

    context "when no test module is active" do
      it "does nothing" do
        subject.deactivate_test_module!
        expect(subject.active_test_module).to be_nil
      end
    end
  end

  describe "#fetch_or_activate_test_suite" do
    let(:test_suite_name) { "my.suite" }
    let(:tracer_span) { double(Datadog::Tracing::SpanOperation, name: test_suite_name) }
    let(:test_suite) { Datadog::CI::TestSuite.new(tracer_span) }

    context "when a test suite is already active" do
      before do
        subject.fetch_or_activate_test_suite(test_suite_name) { test_suite }
      end

      it "returns the active test suite without calling the block" do
        block_spy = spy("block")
        result = subject.fetch_or_activate_test_suite(test_suite_name) do
          block_spy.call
          Datadog::CI::TestSuite.new(tracer_span)
        end

        expect(result).to be(test_suite)
        expect(block_spy).not_to have_received(:call)
      end
    end

    context "when a test suite with this name is not active" do
      before do
        subject.fetch_or_activate_test_suite("another.suite") do
          Datadog::CI::TestSuite.new(double(Datadog::Tracing::SpanOperation))
        end
      end

      it "activates this test suite and returns it" do
        block_spy = spy("block")
        result = subject.fetch_or_activate_test_suite(test_suite_name) do
          block_spy.call
          test_suite
        end

        expect(result).to be(test_suite)
        expect(block_spy).to have_received(:call)
      end
    end

    context "concurrently trying to start the same test suite" do
      include_context "Concurrency test"

      it "activates this test suite only once" do
        repeat do
          subject.deactivate_test_suite!(test_suite_name)

          block_spy = spy("block")

          run_concurrently do
            subject.fetch_or_activate_test_suite(test_suite_name) do
              block_spy.call
              test_suite
            end
          end

          expect(block_spy).to have_received(:call).once
        end
      end
    end
  end

  describe "#fetch_or_activate_test_module" do
    let(:test_module_name) { "my.module" }
    let(:tracer_span) { double(Datadog::Tracing::SpanOperation, name: test_module_name) }
    let(:test_module) { Datadog::CI::TestModule.new(tracer_span) }

    context "when a test module is already active" do
      before do
        subject.fetch_or_activate_test_module { test_module }
      end

      it "returns the active test module without calling the block" do
        block_spy = spy("block")
        result = subject.fetch_or_activate_test_module do
          block_spy.call
          Datadog::CI::TestModule.new(tracer_span)
        end

        expect(result).to be(test_module)
        expect(block_spy).not_to have_received(:call)
      end
    end

    context "when a test module is not active" do
      it "activates this test module and returns it" do
        block_spy = spy("block")
        result = subject.fetch_or_activate_test_module do
          block_spy.call
          test_module
        end

        expect(result).to be(test_module)
        expect(block_spy).to have_received(:call)
      end
    end

    context "concurrently trying to start test module" do
      include_context "Concurrency test"

      it "activates the test module only once" do
        repeat do
          subject.deactivate_test_module!

          block_spy = spy("block")

          run_concurrently do
            subject.fetch_or_activate_test_module do
              block_spy.call
              test_module
            end
          end

          expect(block_spy).to have_received(:call).once
        end
      end
    end
  end

  describe "#fetch_or_activate_test_session" do
    let(:tracer_span) { double(Datadog::Tracing::SpanOperation, name: "test.session") }
    let(:test_session) { Datadog::CI::TestSession.new(tracer_span) }

    context "when a test session is already active" do
      before do
        subject.fetch_or_activate_test_session { test_session }
      end

      it "returns the active test module without calling the block" do
        block_spy = spy("block")
        result = subject.fetch_or_activate_test_session do
          block_spy.call
          Datadog::CI::TestSession.new(tracer_span)
        end

        expect(result).to be(test_session)
        expect(block_spy).not_to have_received(:call)
      end
    end

    context "when a test session is not active" do
      it "activates this test session and returns it" do
        block_spy = spy("block")
        result = subject.fetch_or_activate_test_session do
          block_spy.call
          test_session
        end

        expect(result).to be(test_session)
        expect(block_spy).to have_received(:call)
      end
    end

    context "concurrently trying to start test session" do
      include_context "Concurrency test"

      it "activates the test session only once" do
        repeat do
          subject.deactivate_test_session!

          block_spy = spy("block")

          run_concurrently do
            subject.fetch_or_activate_test_session do
              block_spy.call
              test_session
            end
          end

          expect(block_spy).to have_received(:call).once
        end
      end
    end
  end

  describe "#active_test_suite" do
    let(:test_suite_name) { "my.suite" }
    let(:tracer_span) { double(Datadog::Tracing::SpanOperation, name: test_suite_name) }
    let(:test_suite) { Datadog::CI::TestSuite.new(tracer_span) }

    context "when a test suite is active" do
      before do
        subject.fetch_or_activate_test_suite(test_suite_name) { test_suite }
      end

      it "returns the active test suite" do
        expect(subject.active_test_suite(test_suite_name)).to be(test_suite)
      end
    end

    context "when a test suite with this name is not active" do
      it "returns nil" do
        expect(subject.active_test_suite(test_suite_name)).to be_nil
      end
    end
  end

  describe "#deactivate_test_suite!" do
    let(:test_suite_name) { "my.suite" }
    let(:tracer_span) { double(Datadog::Tracing::SpanOperation, name: test_suite_name) }
    let(:test_suite) { Datadog::CI::TestSuite.new(tracer_span) }

    context "when a test suite is active" do
      before do
        subject.fetch_or_activate_test_suite(test_suite_name) { test_suite }
      end

      it "deactivates the test suite" do
        subject.deactivate_test_suite!(test_suite_name)
        expect(subject.active_test_suite(test_suite_name)).to be_nil
      end
    end

    context "when no test suite is active" do
      it "does nothing" do
        subject.deactivate_test_suite!(test_suite_name)
        expect(subject.active_test_suite(test_suite_name)).to be_nil
      end
    end
  end
end
