# frozen_string_literal: true

require_relative "../../../../../lib/datadog/ci/test_visibility/store/fiber_local"

RSpec.describe Datadog::CI::TestVisibility::Store::FiberLocal do
  subject { described_class.new }

  let(:tracer_span) { double(Datadog::Tracing::SpanOperation, get_tag: "my test") }
  let(:ci_test) { Datadog::CI::Test.new(tracer_span) }
  let(:ci_test2) { Datadog::CI::Test.new(tracer_span) }

  describe "#activate_test" do
    context "when a test is already active" do
      it "raises an error" do
        subject.activate_test(Datadog::CI::Test.new(tracer_span))

        expect { subject.activate_test(ci_test) }.to(
          raise_error(
            RuntimeError,
            "Nested tests are not supported. Currently active test: " \
            "Datadog::CI::Test(name:my test,tracer_span:#[Double Datadog::Tracing::SpanOperation])"
          )
        )
      end
    end

    context "when no test is active" do
      context "when a block is given" do
        it "activates the test for the duration of the block" do
          subject.activate_test(ci_test) do
            expect(subject.active_test).to be(ci_test)
          end

          expect(subject.active_test).to be_nil
        end
      end

      context "when no block is given" do
        it "activates the test" do
          subject.activate_test(ci_test)
          expect(subject.active_test).to be(ci_test)
        end
      end
    end

    context "with multiple fibers" do
      it "create one fiber-local variable per fiber" do
        subject.activate_test(ci_test)

        Fiber.new do
          subject.activate_test(ci_test2)

          expect(subject.active_test).to be(ci_test2)
        end.resume

        expect(subject.active_test).to be(ci_test)
      end
    end

    context "with multiple threads" do
      it "create one thread-local variable per thread" do
        subject.activate_test(ci_test)

        Thread.new do
          subject.activate_test(ci_test2)

          expect(subject.active_test).to be(ci_test2)
        end.join

        expect(subject.active_test).to be(ci_test)
      end
    end
  end

  describe "#deactivate_test" do
    context "when no test is active" do
      it "does nothing" do
        expect { subject.deactivate_test }.not_to raise_error
      end
    end

    context "when a test is active" do
      before { subject.activate_test(ci_test) }

      it "deactivates the test" do
        subject.deactivate_test
        expect(subject.active_test).to be_nil
      end
    end
  end

  describe "#active_test" do
    context "when no test is active" do
      it "returns nil" do
        expect(subject.active_test).to be_nil
      end
    end

    context "when a test is active" do
      before { subject.activate_test(ci_test) }

      it "returns the active test" do
        expect(subject.active_test).to be(ci_test)
      end
    end
  end
end
