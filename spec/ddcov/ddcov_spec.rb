# frozen_string_literal: true

require "datadog_ci_native.#{RUBY_VERSION}_#{RUBY_PLATFORM}"

require_relative "app/model/my_model"
require_relative "app/model/my_model_❤️"
require_relative "app/model/my_struct"
require_relative "calculator/calculator"
require_relative "calculator/code_with_❤️"

RSpec.describe Datadog::CI::TestOptimisation::Coverage::DDCov do
  let(:ignored_path) { nil }
  let(:threading_mode) { :multi }
  let(:use_allocation_tracing) { true }

  subject do
    described_class.new(
      root: root,
      ignored_path: ignored_path,
      threading_mode: threading_mode,
      use_allocation_tracing: use_allocation_tracing
    )
  end

  describe "code coverage collection" do
    let!(:calculator) { Calculator.new }

    context "when allocating and starting coverage without a root" do
      it "throws Runtime error" do
        cov = described_class.allocate

        expect { cov.start }.to raise_error(RuntimeError, "root is required")
      end
    end

    context "when root is the calculator project dir" do
      let(:root) { absolute_path("calculator") }

      it "collects code coverage including Calculator and operations" do
        subject.start

        expect(calculator.add(1, 2)).to eq(3)
        expect(calculator.subtract(1, 2)).to eq(-1)

        coverage = subject.stop

        expect(coverage.size).to eq(3)
        expect(coverage.keys).to include(
          absolute_path("calculator/calculator.rb"),
          absolute_path("calculator/operations/add.rb"),
          absolute_path("calculator/operations/subtract.rb")
        )
      end

      it "supports files with non-ASCII characters" do
        subject.start
        expect(I❤️Ruby.new.call).to eq("I ❤️ Ruby")
        coverage = subject.stop
        expect(coverage.size).to eq(1)
        expect(coverage.keys).to include(absolute_path("calculator/code_with_❤️.rb"))
      end

      context "when ignored_path is set" do
        let(:ignored_path) { absolute_path("calculator/operations") }

        it "collects code coverage excluding ignored_path" do
          subject.start

          expect(calculator.add(1, 2)).to eq(3)
          expect(calculator.subtract(1, 2)).to eq(-1)

          coverage = subject.stop

          expect(coverage.size).to eq(1)
          expect(coverage.keys).to include(absolute_path("calculator/calculator.rb"))
        end
      end
    end

    context "when root is in deeply nested dir" do
      let(:root) { absolute_path("calculator/operations/suboperations") }

      it "does not fail but also does not collect coverages" do
        subject.start

        expect(calculator.add(1, 2)).to eq(3)
        expect(calculator.subtract(1, 2)).to eq(-1)

        coverage = subject.stop

        expect(coverage.size).to eq(0)
      end
    end

    context "when root is in the subdirectory of the project" do
      let(:root) { absolute_path("calculator/operations") }

      it "collects code coverage including operations only" do
        subject.start

        expect(calculator.add(1, 2)).to eq(3)
        expect(calculator.subtract(1, 2)).to eq(-1)

        coverage = subject.stop

        expect(coverage.size).to eq(2)
        expect(coverage.keys).to include(
          absolute_path("calculator/operations/add.rb"),
          absolute_path("calculator/operations/subtract.rb")
        )
      end

      it "clears the coverage data after stopping" do
        subject.start
        expect(calculator.add(1, 2)).to eq(3)
        coverage = subject.stop
        expect(coverage.size).to eq(1)
        expect(coverage.keys).to include(absolute_path("calculator/operations/add.rb"))

        subject.start
        expect(calculator.subtract(1, 2)).to eq(-1)
        coverage = subject.stop
        expect(coverage.size).to eq(1)
        expect(coverage.keys).to include(absolute_path("calculator/operations/subtract.rb"))
      end

      it "does not track coverage when stopped" do
        subject.start
        expect(calculator.add(1, 2)).to eq(3)
        subject.stop

        expect(calculator.subtract(1, 2)).to eq(-1)

        subject.start
        expect(calculator.multiply(1, 2)).to eq(2)
        coverage = subject.stop
        expect(coverage.size).to eq(1)
        expect(coverage.keys).to include(absolute_path("calculator/operations/multiply.rb"))
      end

      it "does not fail if start called several times" do
        subject.start
        expect(calculator.add(1, 2)).to eq(3)

        subject.start
        coverage = subject.stop
        expect(coverage.size).to eq(1)
      end

      it "does not fail if stop called several times" do
        subject.start
        expect(calculator.add(1, 2)).to eq(3)
        coverage = subject.stop
        expect(coverage.size).to eq(1)

        expect(subject.stop).to eq({})
      end

      it "tracks coverage in mixins" do
        subject.start
        expect(calculator.divide(6, 3)).to eq(2)
        coverage = subject.stop
        expect(coverage.size).to eq(2)
        expect(coverage.keys).to include(absolute_path("calculator/operations/divide.rb"))
        expect(coverage.keys).to include(absolute_path("calculator/operations/helpers/calculator_logger.rb"))
      end

      context "multi threaded execution" do
        def thread_local_cov
          Thread.current[:datadog_ci_cov] ||= described_class.new(
            root: root,
            threading_mode: threading_mode,
            use_allocation_tracing: use_allocation_tracing
          )
        end

        context "in single threaded coverage mode" do
          let(:threading_mode) { :single }
          let(:use_allocation_tracing) { false }

          it "collects coverage for each thread separately" do
            t1_queue = Thread::Queue.new
            t2_queue = Thread::Queue.new

            t1 = Thread.new do
              cov = thread_local_cov
              cov.start

              t1_queue << :ready
              expect(t2_queue.pop).to be(:ready)

              expect(calculator.add(1, 2)).to eq(3)
              expect(calculator.multiply(1, 2)).to eq(2)

              t1_queue << :done
              expect(t2_queue.pop).to be :done

              coverage = cov.stop
              expect(coverage.size).to eq(2)
              expect(coverage.keys).to include(absolute_path("calculator/operations/add.rb"))
              expect(coverage.keys).to include(absolute_path("calculator/operations/multiply.rb"))
            end

            t2 = Thread.new do
              cov = thread_local_cov
              cov.start

              t2_queue << :ready
              expect(t1_queue.pop).to be(:ready)

              expect(calculator.subtract(1, 2)).to eq(-1)

              t2_queue << :done
              expect(t1_queue.pop).to be :done

              coverage = cov.stop
              expect(coverage.size).to eq(1)
              expect(coverage.keys).to include(absolute_path("calculator/operations/subtract.rb"))
            end

            [t1, t2].each(&:join)
          end

          context "when allocation tracing is enabled" do
            let(:use_allocation_tracing) { true }

            it "raises an error" do
              expect { thread_local_cov }.to(
                raise_error(ArgumentError, "allocation tracing is not supported in single threaded mode")
              )
            end
          end
        end

        context "in multi threaded code coverage mode" do
          let(:threading_mode) { :multi }

          it "collects coverage for background threads" do
            cov = thread_local_cov
            cov.start

            t = Thread.new do
              expect(calculator.add(1, 2)).to eq(3)
            end

            expect(calculator.multiply(1, 2)).to eq(2)
            t.join

            coverage = cov.stop
            expect(coverage.size).to eq(2)
            expect(coverage.keys).to include(absolute_path("calculator/operations/add.rb"))
            expect(coverage.keys).to include(absolute_path("calculator/operations/multiply.rb"))
          end

          it "collects coverage for background threads that started before the coverage collection" do
            jobs_queue = Thread::Queue.new
            background_jobs_worker = Thread.new do
              loop do
                job = jobs_queue.pop
                break if job == :done

                job.call
              end
            end

            cov = described_class.new(root: root, threading_mode: :multi)
            cov.start

            jobs_queue << -> { expect(calculator.add(1, 2)).to eq(3) }
            jobs_queue << -> { expect(calculator.multiply(1, 2)).to eq(2) }

            jobs_queue << :done

            background_jobs_worker.join

            coverage = cov.stop
            expect(coverage.size).to eq(2)
            expect(coverage.keys).to include(absolute_path("calculator/operations/add.rb"))
            expect(coverage.keys).to include(absolute_path("calculator/operations/multiply.rb"))
          end

          it "does not track coverage when stopped" do
            subject.start
            expect(calculator.add(1, 2)).to eq(3)
            subject.stop

            expect(calculator.subtract(1, 2)).to eq(-1)

            subject.start
            expect(calculator.multiply(1, 2)).to eq(2)
            coverage = subject.stop
            expect(coverage.size).to eq(1)
            expect(coverage.keys).to include(absolute_path("calculator/operations/multiply.rb"))
          end
        end

        context "when threading mode is invalid" do
          let(:threading_mode) { :invalid_mode }

          it "raises an error" do
            expect { described_class.new(root: root, threading_mode: threading_mode) }.to(
              raise_error(ArgumentError, "threading mode is invalid")
            )
          end
        end
      end
    end

    context "root in app folder" do
      let(:root) { absolute_path("app") }

      context "allocation tracing is enabled" do
        it "tracks coverage for empty model" do
          subject.start

          MyModel.new
          expect(calculator.add(1, 2)).to eq(3)

          coverage = subject.stop
          expect(coverage.size).to eq(3)
          expect(coverage.keys).to include(absolute_path("app/model/my_model.rb"))
          expect(coverage.keys).to include(absolute_path("app/model/my_parent_model.rb"))
          expect(coverage.keys).to include(absolute_path("app/model/my_grandparent_model.rb"))

          MyModel.new

          subject.start
          coverage = subject.stop
          expect(coverage.size).to eq(0)
        end

        it "does not break when encountering anonymous class or internal Ruby classes implemented in C" do
          subject.start

          MyModel.new
          c = Class.new(Object) do
          end
          c.new

          # Trying to get non-existing constant could caise freezing of Ruby process when
          # not safely getting source location of the constant in NEWOBJ tracepoint.
          begin
            Object.const_get(:fdsfdsfdsfds)
          rescue
            nil
          end

          coverage = subject.stop
          expect(coverage.size).to eq(3)
          expect(coverage.keys).to include(absolute_path("app/model/my_model.rb"))
          expect(coverage.keys).to include(absolute_path("app/model/my_parent_model.rb"))
          expect(coverage.keys).to include(absolute_path("app/model/my_grandparent_model.rb"))
        end

        it "tracks coverage for structs" do
          subject.start

          User.new("john doe", "johndoe@mail.test")

          coverage = subject.stop
          expect(coverage.size).to eq(1)
          expect(coverage.keys).to include(absolute_path("app/model/my_struct.rb"))
        end

        it "tracks coverage for objects defined with emojis" do
          subject.start

          MyModel❤️.new

          coverage = subject.stop
          expect(coverage.size).to eq(1)
          expect(coverage.keys).to include(absolute_path("app/model/my_model_❤️.rb"))
        end

        context "Object.const_source_location is redefined in tests" do
          context "returns invalid values" do
            before do
              allow(Object).to receive(:const_source_location).and_return([-1, -1])
            end

            it "does not break" do
              subject.start

              User.new("john doe", "johndoe@mail.test")

              coverage = subject.stop
              expect(coverage.size).to eq(0)
            end
          end

          context "returns nil" do
            before do
              allow(Object).to receive(:const_source_location).and_return(nil)
            end

            it "does not break" do
              subject.start

              User.new("john doe", "johndoe@mail.test")

              coverage = subject.stop
              expect(coverage.size).to eq(0)
            end
          end

          context "returns empty array" do
            before do
              allow(Object).to receive(:const_source_location).and_return([])
            end

            it "does not break" do
              subject.start

              User.new("john doe", "johndoe@mail.test")

              coverage = subject.stop
              expect(coverage.size).to eq(0)
            end
          end

          context "returns empty nested array" do
            before do
              allow(Object).to receive(:const_source_location).and_return([[]])
            end

            it "does not break" do
              subject.start

              User.new("john doe", "johndoe@mail.test")

              coverage = subject.stop
              expect(coverage.size).to eq(0)
            end
          end

          context "raises" do
            before do
              allow(Object).to receive(:const_source_location).and_raise(StandardError)
            end

            it "does not break" do
              subject.start

              User.new("john doe", "johndoe@mail.test")

              coverage = subject.stop
              expect(coverage.size).to eq(0)
            end
          end
        end

        context "Data structs available since Ruby 3.2" do
          before do
            if RUBY_VERSION < "3.2"
              skip
            else
              require_relative "app/model/measure"
            end
          end

          it "tracks coverage for Data structs" do
            subject.start

            Measure.new(100, "km")

            coverage = subject.stop
            expect(coverage.size).to eq(1)
            expect(coverage.keys).to include(absolute_path("app/model/measure.rb"))
          end
        end
      end

      context "allocation tracing is disabled" do
        let(:use_allocation_tracing) { false }

        it "does not track coverage for empty model" do
          subject.start

          MyModel.new
          expect(calculator.add(1, 2)).to eq(3)

          coverage = subject.stop
          expect(coverage.size).to eq(0)
        end
      end
    end
  end
end
