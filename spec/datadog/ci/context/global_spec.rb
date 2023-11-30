RSpec.describe Datadog::CI::Context::Global do
  subject { described_class.new }

  let(:tracer_span) { double(Datadog::Tracing::SpanOperation, name: "test.session", service: "my-service") }
  let(:session) { Datadog::CI::TestSession.new(tracer_span) }
  let(:test_module) { Datadog::CI::TestModule.new(tracer_span) }

  describe "#activate_test_session!" do
    context "when a test session is already active" do
      before do
        subject.activate_test_session!(Datadog::CI::TestSession.new(tracer_span))
      end

      it "raises an error" do
        expect { subject.activate_test_session!(session) }.to(
          raise_error(
            RuntimeError,
            "Nested test sessions are not supported. Currently active test session: " \
            "#{session}"
          )
        )
      end
    end

    context "when no test session is active" do
      it "activates the test session" do
        subject.activate_test_session!(session)
        expect(subject.active_test_session).to be(session)
      end
    end
  end

  describe "#service" do
    context "when a test session is active" do
      before do
        subject.activate_test_session!(session)
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

        subject.activate_test_session!(session)
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
        subject.activate_test_session!(session)
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
        subject.activate_test_session!(session)
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

  describe "#activate_test_module!" do
    context "when a test module is already active" do
      before do
        subject.activate_test_module!(Datadog::CI::TestModule.new(tracer_span))
      end

      it "raises an error" do
        expect { subject.activate_test_module!(test_module) }.to(
          raise_error(
            RuntimeError,
            "Nested test modules are not supported. Currently active test module: " \
            "#{test_module}"
          )
        )
      end
    end

    context "when no test module is active" do
      it "activates the test module" do
        subject.activate_test_module!(test_module)
        expect(subject.active_test_module).to be(test_module)
      end
    end
  end

  describe "active_test_module" do
    context "when a test module is active" do
      before do
        subject.activate_test_module!(test_module)
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
        subject.activate_test_module!(test_module)
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
end
