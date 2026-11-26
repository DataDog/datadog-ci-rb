# frozen_string_literal: true

# Run by line_coverage_spec.rb in a child process, so that GC.stress and GC.auto_compact stay
# out of the spec process. Each file loads twice while a compacting GC is in progress: a
# TracePoint that runs just before the collector's compile hook starts that GC, and in stress
# mode turns on GC.stress, so that the first object allocation finishes it, compaction
# included. One that runs just after records the GC state and turns GC.stress off. After each
# load a test runs the file's nested code. Prints, for each mode, how many loads recorded every
# nested line and after how many second loads the GC was still marking.
require "json"
require "datadog/ci/test_impact_analysis/coverage/line_coverage"
require "datadog_ci_native.#{RUBY_VERSION}_#{RUBY_PLATFORM}"

coverage = Datadog::CI::TestImpactAnalysis::Coverage
root, directory = ARGV
markers = %w[block_line rescue_line ensure_line inner_line]
source = lambda do |name, generation|
  <<~RUBY
    module #{name}
      class Thing
        def map(x)
          [1, 2, 3].map do |v|
            v * x + #{generation} # block_line
          end
        end

        def rescued
          raise ArgumentError, "x"
        rescue ArgumentError => e
          e.message # rescue_line
        ensure
          @done = #{generation} # ensure_line
        end

        class Inner
          def call
            [:inner, #{generation}] # inner_line
          end
        end
      end
    end
  RUBY
end

GC.auto_compact = true
mode = nil
state_after_hook = nil
after_hook = TracePoint.new(:script_compiled) do
  next unless mode

  state_after_hook = GC.latest_gc_info(:state)
  GC.stress = false
end
# Hooks run newest first: this one runs after the collector's, the next one before it.
after_hook.enable
line_coverage = coverage::LineCoverage.start(root: root, ignored_paths: [])
before_hook = TracePoint.new(:script_compiled) do
  next unless mode

  # Nothing allocates between this GC.start and the collector's hook.
  GC.start(full_mark: true, immediate_mark: false, immediate_sweep: false)
  GC.stress = true if mode == "stress"
end
before_hook.enable

results = {}
test_id = 0
%w[run stress].each do |current_mode|
  complete = 0
  marking = 0
  5.times do |index|
    name = "GcDuringArming#{current_mode.capitalize}#{index}"
    path = File.join(directory, "#{current_mode}_#{index}.rb")
    relative = nil
    # The first load classifies a new path; the second compiles the same path again.
    2.times do |generation|
      text = source.call(name, generation)
      File.write(path, text)
      relative ||= File.realpath(path).delete_prefix(File.join(root, ""))
      mode = current_mode
      load path
      mode = nil
      marking += 1 if generation == 1 && state_after_hook == :marking

      test_id += 1
      line_coverage.start_test(test_id)
      thing = Object.const_get(name)::Thing.new
      thing.map(2)
      thing.rescued
      Object.const_get(name)::Thing::Inner.new.call
      _count, packed = line_coverage.finish_test(test_id, [])
      bitmap = coverage::LineFiles.unpack(packed)[relative]
      lines = bitmap ? coverage::LineFiles.lines(bitmap) : []
      expected = text.lines.each_with_index.filter_map do |line, number|
        number + 1 if markers.any? { |marker| line.include?("# #{marker}") }
      end
      complete += 1 if (expected - lines).empty?
    end
  end
  results[current_mode] = {"complete" => complete, "marking after the second load" => marking}
end
before_hook.disable
after_hook.disable
results["gc_disable_no_rest"] = coverage::LineCollector.stats.fetch(:gc_disable_no_rest)
puts JSON.generate(results)
