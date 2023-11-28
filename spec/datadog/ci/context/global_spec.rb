RSpec.describe Datadog::CI::Context::Global do
  subject { described_class.new }

  let(:tracer_span) { double(Datadog::Tracing::SpanOperation, name: "test.session") }
  let(:session) { Datadog::CI::TestSession.new(tracer_span) }

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
end
