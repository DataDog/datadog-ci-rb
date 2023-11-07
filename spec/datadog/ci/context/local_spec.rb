RSpec.describe Datadog::CI::Context::Local do
  subject { described_class.new }

  let(:tracer_span) { double(Datadog::Tracing::SpanOperation) }
  let(:ci_test) { Datadog::CI::Test.new(tracer_span) }
  let(:ci_test2) { Datadog::CI::Test.new(tracer_span) }

  def fiber_active_tests
    Thread.current.keys.select { |k| k.to_s.start_with?("datadog_ci_active_test_") }
  end

  describe "#activate_test!" do
    context "when a test is already active" do
      it "raises an error" do
        subject.activate_test!(Datadog::CI::Test.new(tracer_span))

        expect { subject.activate_test!(ci_test) }.to raise_error(RuntimeError, /Nested tests are not supported/)
      end
    end

    context "when no test is active" do
      context "when a block is given" do
        it "activates the test for the duration of the block" do
          subject.activate_test!(ci_test) do
            expect(subject.active_test).to be(ci_test)
          end

          expect(subject.active_test).to be_nil
        end
      end

      context "when no block is given" do
        it "activates the test" do
          subject.activate_test!(ci_test)
          expect(subject.active_test).to be(ci_test)
        end
      end
    end

    context "with multiple local contexts" do
      let(:local_context_1) { described_class.new }
      let(:local_context_2) { described_class.new }

      it "does not share the active test" do
        local_context_1.activate_test!(ci_test)
        local_context_2.activate_test!(ci_test2)

        expect(local_context_1.active_test).to be(ci_test)
        expect(local_context_2.active_test).to be(ci_test2)
      end
    end

    context "with multiple fibers" do
      it "create one fiber-local variable per fiber" do
        subject.activate_test!(ci_test)

        Fiber.new do
          expect { subject.activate_test!(ci_test2) }
            .to change { fiber_active_tests.size }.from(0).to(1)
        end.resume

        expect(subject.active_test).to be(ci_test)
      end
    end

    context "with multiple threads" do
      it "create one thread-local variable per thread" do
        subject.activate_test!(ci_test)

        Thread.new do
          expect { subject.activate_test!(ci_test2) }
            .to change { fiber_active_tests.size }.from(0).to(1)
        end.join

        expect(subject.active_test).to be(ci_test)
      end
    end
  end

  describe "#deactivate_test!" do
    context "when no test is active" do
      it "does nothing" do
        expect { subject.deactivate_test!(ci_test) }.not_to raise_error
      end
    end

    context "when a test is active" do
      before { subject.activate_test!(ci_test) }

      context "when the test is the active test" do
        it "deactivates the test" do
          subject.deactivate_test!(ci_test)
          expect(subject.active_test).to be_nil
        end
      end

      context "when the test is not the active test" do
        it "raises an error" do
          expect { subject.deactivate_test!(Datadog::CI::Test.new(tracer_span)) }
            .to raise_error(RuntimeError, /Trying to deactivate test/)
        end
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
      before { subject.activate_test!(ci_test) }

      it "returns the active test" do
        expect(subject.active_test).to be(ci_test)
      end
    end

    context "with multiple local contexts" do
      let(:local_context_1) { described_class.new }
      let(:local_context_2) { described_class.new }

      it "does not share the active test" do
        local_context_1.activate_test!(ci_test)
        local_context_2.activate_test!(ci_test2)

        expect(local_context_1.active_test).to be(ci_test)
        expect(local_context_2.active_test).to be(ci_test2)
      end
    end
  end
end
