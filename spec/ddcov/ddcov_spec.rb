# frozen_string_literal: true

require "datadog_cov.#{RUBY_VERSION}_#{RUBY_PLATFORM}"

require_relative "calculator/calculator"
require_relative "calculator/code_with_❤️"

RSpec.describe Datadog::CI::ITR::Coverage::DDCov do
  def absolute_path(path)
    File.expand_path(File.join(__dir__, path))
  end

  let(:ignored_path) { nil }
  subject { described_class.new(root: root, mode: mode, ignored_path: ignored_path) }

  describe "code coverage collection" do
    let!(:calculator) { Calculator.new }

    context "in files mode" do
      let(:mode) { :files }

      context "when allocating and starting coverage without a root" do
        it "does not fail" do
          cov = described_class.allocate
          cov.start
          expect(calculator.add(1, 2)).to eq(3)

          coverage = cov.stop
          expect(coverage).to eq({})
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

        it "does not support files with non-ASCII characters yet due to additional overhead of UTF-8 strings parsing" do
          subject.start
          expect(I❤️Ruby.new.call).to eq("I ❤️ Ruby")
          coverage = subject.stop
          expect(coverage.size).to eq(1)
          # this string will have a bunch of UTF-8 codepoints in it
          expect(coverage.keys.first).to include("calculator/code_with_")
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
            Thread.current[:datadog_ci_cov] ||= described_class.new(root: root)
          end

          it "collects coverage for each thread separately" do
            t1_queue = Queue.new
            t2_queue = Queue.new

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
        end
      end
    end

    context "in lines mode" do
      let(:mode) { :lines }
      let(:root) { absolute_path("calculator") }

      it "collects code coverage with lines" do
        subject.start

        expect(calculator.add(1, 2)).to eq(3)
        expect(calculator.subtract(1, 2)).to eq(-1)

        coverage = subject.stop

        expect(coverage.size).to eq(3)
        expect(coverage).to eq({
          absolute_path("calculator/calculator.rb") => {17 => true, 21 => true},
          absolute_path("calculator/operations/add.rb") => {5 => true},
          absolute_path("calculator/operations/subtract.rb") => {5 => true}
        })
      end
    end
  end
end
