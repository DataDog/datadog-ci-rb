# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/utils/error_stack"

RSpec.describe Datadog::CI::Utils::ErrorStack do
  let(:library) { described_class::LIBRARY_DIRECTORIES.first }
  let(:wrapper) { "#{library}contrib/file_access/instrumentation.rb:63" }

  def exception_with(backtrace, error_class: Errno::ENOENT, message: "missing.json")
    error = error_class.new(message)
    error.set_backtrace(backtrace)
    error
  end

  describe ".full_message" do
    it "formats a stack without datadog-ci frames as the tracer does" do
      error = begin
        begin
          raise ArgumentError, "inner"
        rescue
          raise "outer\nsecond line"
        end
      rescue => e
        e
      end

      expect(described_class.full_message(error)).to eq(Datadog::Core::Error.build_from(error).backtrace)
    end

    it "moves the frame that raised to the caller of the datadog-ci frames above it" do
      error = exception_with([
        "#{wrapper}:in `read'",
        "#{wrapper}:in `read'",
        "/repo/test/fixture_test.rb:10:in `block in <class:FixtureTest>'",
        "/repo/test/fixture_test.rb:5:in `run'"
      ])

      expect(described_class.full_message(error)).to eq(
        "/repo/test/fixture_test.rb:10:in `read': No such file or directory - missing.json (Errno::ENOENT)\n" \
        "\tfrom /repo/test/fixture_test.rb:10:in `block in <class:FixtureTest>'\n" \
        "\tfrom /repo/test/fixture_test.rb:5:in `run'\n"
      )
    end

    it "keeps the label of the frame that raised in the format of Ruby 3.4" do
      error = exception_with([
        "#{wrapper}:in 'File#initialize'",
        "#{wrapper}:in 'Datadog::CI::Contrib::FileAccess::Instrumentation::InstanceMethods#initialize'",
        "#{library}contrib/file_access/instrumentation.rb:20:in 'IO.open'",
        "/repo/test/fixture_test.rb:12:in 'FixtureTest#test_open'"
      ])

      expect(described_class.full_message(error).lines.first).to eq(
        "/repo/test/fixture_test.rb:12:in 'File#initialize': " \
        "No such file or directory - missing.json (Errno::ENOENT)\n"
      )
      expect(described_class.full_message(error)).not_to include(library)
    end

    it "keeps datadog-ci frames below the first frame of other code" do
      backtrace = [
        "/repo/test/fixture_test.rb:10:in `block in <class:FixtureTest>'",
        "#{library}contrib/minitest/test.rb:80:in `run'",
        "/gems/minitest/lib/minitest.rb:300:in `run_one_method'"
      ]

      expect(described_class.full_message(exception_with(backtrace))).to eq(
        "#{backtrace[0]}: No such file or directory - missing.json (Errno::ENOENT)\n" \
        "\tfrom #{backtrace[1]}\n" \
        "\tfrom #{backtrace[2]}\n"
      )
    end

    it "keeps a stack that has only datadog-ci frames" do
      backtrace = ["#{wrapper}:in `read'", "#{library}test_tracing/component.rb:40:in `trace_test'"]

      expect(described_class.full_message(exception_with(backtrace))).to eq(
        "#{backtrace[0]}: No such file or directory - missing.json (Errno::ENOENT)\n" \
        "\tfrom #{backtrace[1]}\n"
      )
    end

    it "drops the frame that raised when it has no label to move" do
      error = exception_with([wrapper, "/repo/test/fixture_test.rb:10:in `block in <class:FixtureTest>'"])

      expect(described_class.full_message(error)).to eq(
        "/repo/test/fixture_test.rb:10:in `block in <class:FixtureTest>': " \
        "No such file or directory - missing.json (Errno::ENOENT)\n"
      )
    end

    it "cleans the stack of each cause and stops at a cause seen before" do
      cause = exception_with(["#{wrapper}:in `read'", "/repo/lib/loader.rb:3:in `load'"])
      error = exception_with(["/repo/test/fixture_test.rb:20:in `test_load'"], error_class: RuntimeError, message: "outer")
      allow(error).to receive(:cause).and_return(cause)
      allow(cause).to receive(:cause).and_return(error)

      expect(described_class.full_message(error)).to eq(
        "/repo/test/fixture_test.rb:20:in `test_load': outer (RuntimeError)\n" \
        "/repo/lib/loader.rb:3:in `read': No such file or directory - missing.json (Errno::ENOENT)\n" \
        "\tfrom /repo/lib/loader.rb:3:in `load'\n"
      )
    end

    it "leaves out an exception that was never raised" do
      expect(described_class.full_message(RuntimeError.new("never raised"))).to eq("")
    end
  end

  describe ".without_library_frames" do
    it "returns the backtrace itself when its first frame is not datadog-ci's" do
      backtrace = ["/repo/test/fixture_test.rb:10:in `block in <class:FixtureTest>'", "#{wrapper}:in `read'"]

      expect(described_class.without_library_frames(backtrace)).to equal(backtrace)
    end
  end
end
