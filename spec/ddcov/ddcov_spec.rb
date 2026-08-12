# frozen_string_literal: true

require "datadog_ci_native.#{RUBY_VERSION}_#{RUBY_PLATFORM}"

require_relative "app/model/my_model"
require_relative "app/model/my_model_❤️"
require_relative "app/model/my_struct"
require_relative "app/model/dynamic_model"
require_relative "calculator/calculator"
require_relative "calculator/code_with_❤️"

RSpec.describe Datadog::CI::TestImpactAnalysis::Coverage::DDCov do
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

    context "when initialization arguments are malformed" do
      it "rejects non-hash options and non-string paths" do
        expect { described_class.new(nil) }.to raise_error(TypeError)
        expect do
          described_class.new(root: Object.new, threading_mode: :multi)
        end.to raise_error(TypeError)
        expect do
          described_class.new(root: "/tmp", ignored_path: Object.new, threading_mode: :multi)
        end.to raise_error(TypeError)
      end

      it "rejects paths containing null bytes" do
        expect do
          described_class.new(root: "/tmp\0other", threading_mode: :multi)
        end.to raise_error(ArgumentError)
        expect do
          described_class.new(root: "/tmp", ignored_path: "/tmp\0other", threading_mode: :multi)
        end.to raise_error(ArgumentError)
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

      context "when ignored_path equals root" do
        let(:ignored_path) { absolute_path("calculator") }

        it "collects no coverage since everything is ignored" do
          subject.start

          expect(calculator.add(1, 2)).to eq(3)
          expect(calculator.subtract(1, 2)).to eq(-1)

          coverage = subject.stop

          expect(coverage).to be_empty
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

      it "does not crash on eval'd code and still tracks regular coverage" do
        subject.start

        # eval'd code has no source file - should not crash
        eval("1 + 1", binding, __FILE__, __LINE__)
        eval("def dynamic_method; 42; end", binding, __FILE__, __LINE__)
        dynamic_method

        # Regular code should still be tracked
        expect(calculator.add(1, 2)).to eq(3)

        coverage = subject.stop
        expect(coverage.keys).to include(absolute_path("calculator/operations/add.rb"))
      end

      it "tracks coverage for code that raises exceptions" do
        subject.start

        begin
          calculator.divide(1, 0)
        rescue ZeroDivisionError
          # Expected - division by zero
        end

        coverage = subject.stop

        # Coverage should still be recorded for code that was executed before the exception
        expect(coverage.keys).to include(absolute_path("calculator/operations/divide.rb"))
        expect(coverage.keys).to include(absolute_path("calculator/operations/helpers/calculator_logger.rb"))
      end

      it "does not crash on dynamically defined methods via define_method" do
        klass = Class.new do
          define_method(:dynamic_add) do |a, b|
            a + b
          end
        end

        subject.start

        # Dynamic method execution - the method itself has no file source
        result = klass.new.dynamic_add(1, 2)
        expect(result).to eq(3)

        # Also call regular tracked code
        expect(calculator.add(1, 2)).to eq(3)

        coverage = subject.stop

        # Regular code should still be tracked
        expect(coverage.keys).to include(absolute_path("calculator/operations/add.rb"))
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

          it "collects distinct dynamic sources executed by many threads" do
            root = absolute_path("dynamic/threaded")
            collector = described_class.new(
              root: root,
              threading_mode: :multi,
              use_allocation_tracing: false
            )
            sources = Array.new(256) do |index|
              path = File.join(root, "#{index}.rb")
              [path, RubyVM::InstructionSequence.compile("Thread.pass\n", path, path)]
            end

            collector.start
            sources.each_slice(32).map do |slice|
              Thread.new { slice.each { |_, iseq| iseq.eval } }
            end.each(&:join)
            coverage = collector.stop

            expected_files = sources.map(&:first)
            expect((coverage.keys & expected_files).size).to eq(expected_files.size)
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

    context "when dynamic source filenames stress the line-event cache" do
      let(:root) { absolute_path("dynamic/included") }
      let(:use_allocation_tracing) { false }

      it "does not confuse a new source file with a discarded excluded file" do
        included_dir = absolute_path("dynamic/included")
        excluded_dir = absolute_path("dynamic/excluded")
        spacer_path = absolute_path("dynamic/spacer.rb")
        spacer = RubyVM::InstructionSequence.compile("nil\n", spacer_path, spacer_path)
        execute_transient_source = lambda do |directory, basename|
          path = File.join(directory, basename)
          RubyVM::InstructionSequence.compile("nil\n", path, path).eval
        end
        expected_files = []

        subject.start

        # Valgrind makes each forced full-heap collection extremely expensive.
        # Ordinary CI keeps the full pointer-reuse stress; memcheck only needs
        # enough iterations to exercise GC ownership and marking.
        iterations = (ENV["RUBY_MEMCHECK_RUNNING"] == "1") ? 20 : 2_000

        iterations.times do |index|
          basename = format("%04d.rb", index)
          execute_transient_source.call(excluded_dir, basename)
          GC.start(full_mark: true, immediate_sweep: true)

          included_path = File.join(included_dir, basename)
          included_iseq = RubyVM::InstructionSequence.compile("nil\n", included_path, included_path)
          expected_files << included_path

          # Keep the consecutive-filename fast path from masking the direct
          # cache behavior under test.
          spacer.eval
          included_iseq.eval
        end

        coverage = subject.stop

        recorded_files = coverage.keys & expected_files
        expect(recorded_files.size).to eq(expected_files.size)
      end

      it "records more distinct sources than the direct cache can hold" do
        subject.start
        expected_files = Array.new(1_100) do |index|
          path = File.join(root, "overflow-#{index}.rb")
          source = RubyVM::InstructionSequence.compile("nil\n", path, path)

          source.eval
          path
        end

        coverage = subject.stop

        expect((coverage.keys & expected_files).size).to eq(expected_files.size)
      end

      it "keeps cached filenames valid across heap compaction" do
        skip "Ruby does not support heap compaction" unless GC.respond_to?(:compact)

        first_path = File.join(root, "before-compaction.rb")
        second_path = File.join(root, "after-compaction.rb")
        spacer_path = absolute_path("dynamic/excluded/compaction-spacer.rb")
        first_source = RubyVM::InstructionSequence.compile("nil\n", first_path, first_path)
        second_source = RubyVM::InstructionSequence.compile("nil\n", second_path, second_path)
        spacer = RubyVM::InstructionSequence.compile("nil\n", spacer_path, spacer_path)

        subject.start
        first_source.eval
        spacer.eval
        GC.compact
        first_source.eval
        second_source.eval
        coverage = subject.stop

        expect(coverage.keys).to include(first_path, second_path)
      end
    end

    context "when paths only share a textual prefix" do
      let(:root) { absolute_path("dynamic/app") }
      let(:use_allocation_tracing) { false }

      it "does not include files from a sibling directory" do
        included_path = File.join(root, "model.rb")
        sibling_path = absolute_path("dynamic/application/model.rb")
        included_source = RubyVM::InstructionSequence.compile("nil\n", included_path, included_path)
        sibling_source = RubyVM::InstructionSequence.compile("nil\n", sibling_path, sibling_path)

        subject.start
        sibling_source.eval
        included_source.eval
        coverage = subject.stop

        expect(coverage.keys).to include(included_path)
        expect(coverage.keys).not_to include(sibling_path)
      end

      context "when an ignored path is configured" do
        let(:root) { absolute_path("dynamic") }
        let(:ignored_path) { absolute_path("dynamic/vendor") }

        it "does not ignore a sibling directory with the same prefix" do
          ignored_file = File.join(ignored_path, "dependency.rb")
          included_file = absolute_path("dynamic/vendorized/application.rb")
          ignored_source = RubyVM::InstructionSequence.compile("nil\n", ignored_file, ignored_file)
          included_source = RubyVM::InstructionSequence.compile("nil\n", included_file, included_file)

          subject.start
          ignored_source.eval
          included_source.eval
          coverage = subject.stop

          expect(coverage.keys).to include(included_file)
          expect(coverage.keys).not_to include(ignored_file)
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
          expect(coverage.size).to eq(4)
          expect(coverage.keys).to include(absolute_path("app/model/my_model.rb"))
          expect(coverage.keys).to include(absolute_path("app/model/my_parent_model.rb"))
          expect(coverage.keys).to include(absolute_path("app/model/my_grandparent_model.rb"))
          expect(coverage.keys).to include(absolute_path("app/concerns/queryable.rb"))

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
          expect(coverage.size).to eq(4)
          expect(coverage.keys).to include(absolute_path("app/model/my_model.rb"))
          expect(coverage.keys).to include(absolute_path("app/model/my_parent_model.rb"))
          expect(coverage.keys).to include(absolute_path("app/model/my_grandparent_model.rb"))
          expect(coverage.keys).to include(absolute_path("app/concerns/queryable.rb"))
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

        context "GC stress during coverage collection" do
          it "survives GC during allocation tracing" do
            subject.start

            10_000.times do |i|
              MyModel.new
              GC.start(full_mark: true, immediate_sweep: true) if i % 100 == 0
            end

            coverage = subject.stop
            expect(coverage.keys).to include(absolute_path("app/model/my_model.rb"))
            expect(coverage.keys).to include(absolute_path("app/model/my_parent_model.rb"))
            expect(coverage.keys).to include(absolute_path("app/model/my_grandparent_model.rb"))
            expect(coverage.keys).to include(absolute_path("app/concerns/queryable.rb"))
          end

          it "reuses cached class files after heap compaction" do
            skip "Ruby does not support heap compaction" unless GC.respond_to?(:compact)

            namespace_name = :DDCovCompactionStress
            namespace = Module.new
            Object.const_set(namespace_name, namespace)
            expected_files = Array.new(128) do |index|
              path = absolute_path("app/generated/compaction-#{index}.rb")
              RubyVM::InstructionSequence.compile(
                "class #{namespace_name}::Model#{index}; end",
                path,
                path
              ).eval
              path
            end
            classes = namespace.constants(false).map { |name| namespace.const_get(name) }

            subject.start
            classes.each(&:new)
            first_coverage = subject.stop
            GC.compact
            subject.start
            classes.reverse_each(&:new)
            second_coverage = subject.stop

            expect((first_coverage.keys & expected_files).size).to eq(expected_files.size)
            expect((second_coverage.keys & expected_files).size).to eq(expected_files.size)
          ensure
            Object.send(:remove_const, namespace_name) if Object.const_defined?(namespace_name, false)
          end
        end

        context "allocated-class cache stress" do
          it "records more distinct classes than the direct cache can hold" do
            namespace_name = :DDCovAllocatedClassCacheStress
            namespace = Module.new
            Object.const_set(namespace_name, namespace)
            expected_files = Array.new(4_200) do |index|
              path = absolute_path("app/generated/allocated-#{index}.rb")
              RubyVM::InstructionSequence.compile(
                "class #{namespace_name}::Model#{index}; end",
                path,
                path
              ).eval
              path
            end
            classes = namespace.constants(false).map { |name| namespace.const_get(name) }

            subject.start
            classes.each(&:new)
            coverage = subject.stop

            expect((coverage.keys & expected_files).size).to eq(expected_files.size)
          ensure
            Object.send(:remove_const, namespace_name) if Object.const_defined?(namespace_name, false)
          end

          it "does not confuse a redefined constant with its previous class" do
            namespace_name = :DDCovRedefinedClassStress
            namespace = Module.new
            Object.const_set(namespace_name, namespace)
            first_path = absolute_path("app/generated/first-model.rb")
            second_path = absolute_path("app/generated/second-model.rb")
            RubyVM::InstructionSequence.compile(
              "class #{namespace_name}::Model; end",
              first_path,
              first_path
            ).eval
            first_class = namespace.const_get(:Model)

            subject.start
            first_class.new
            first_coverage = subject.stop

            namespace.send(:remove_const, :Model)
            RubyVM::InstructionSequence.compile(
              "class #{namespace_name}::Model; end",
              second_path,
              second_path
            ).eval
            second_class = namespace.const_get(:Model)

            subject.start
            second_class.new
            second_coverage = subject.stop

            expect(first_coverage.keys).to include(first_path)
            expect(second_coverage.keys).to include(second_path)
            expect(second_coverage.keys).not_to include(first_path)
          ensure
            Object.send(:remove_const, namespace_name) if Object.const_defined?(namespace_name, false)
          end
        end

        context "BasicObject subclasses" do
          it "handles objects that inherit from BasicObject without crashing" do
            # BasicObject doesn't have the standard Object methods like `class`
            # This tests that the C extension handles edge cases gracefully
            klass = Class.new(BasicObject) do
              def initialize
              end
            end

            subject.start

            # BasicObject subclass allocation - should not crash
            klass.new

            # Normal allocation to verify coverage still works
            MyModel.new

            coverage = subject.stop
            expect(coverage.keys).to include(absolute_path("app/model/my_model.rb"))
          end
        end

        context "rapid start/stop cycles" do
          it "handles many rapid start/stop cycles with allocation tracing" do
            100.times do
              subject.start
              MyModel.new
              coverage = subject.stop
              expect(coverage.keys).to include(absolute_path("app/model/my_model.rb"))
            end
          end
        end

        context "method_missing dynamic dispatch" do
          it "tracks coverage for classes using method_missing" do
            subject.start

            model = DynamicModel.new
            result = model.any_method_name(1, 2, 3)

            coverage = subject.stop

            expect(result).to eq("called any_method_name with [1, 2, 3]")
            expect(coverage.keys).to include(absolute_path("app/model/dynamic_model.rb"))
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
