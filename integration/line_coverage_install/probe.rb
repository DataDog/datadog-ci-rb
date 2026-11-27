# frozen_string_literal: true

# Checks an installed datadog-ci the way a test session uses it: whether its native extension has per-test line
# coverage, which VM headers it was built with or why it has none, and the lines it records for four tests of a
# small file. Writes the result as JSON to the path in ARGV[0]. Datadog's log goes to standard output.
require "json"
require "tmpdir"

result = {"ruby" => RUBY_VERSION}

# Some cases install datadog-ci without its dependencies, and then the gem cannot be activated: load it from its
# directories instead.
unless defined?(Bundler)
  begin
    gem "datadog-ci"
  rescue Gem::LoadError => e
    result["activation_error"] = e.message
    spec = Gem::Specification.find_all_by_name("datadog-ci").first
    $LOAD_PATH.unshift(spec.extension_dir, *spec.full_require_paths)
  end
end

require "datadog/ci"
begin
  require "datadog_ci_native.#{RUBY_VERSION}_#{RUBY_PLATFORM}"
rescue LoadError => e
  result["extension_load_error"] = e.message
end
require "datadog/ci/test_impact_analysis/coverage/line_coverage"

coverage = Datadog::CI::TestImpactAnalysis::Coverage
%w[datadog datadog-ruby_core_source].each do |name|
  result[name] = Gem::Specification.find_all_by_name(name).map { |spec| spec.version.to_s }.sort.join(", ")
end
if defined?(coverage::LineCollector)
  result["supported"] = coverage::LineCollector.supported?
  result["vm_headers"] = coverage::LineCollector.vm_headers
  result["unsupported_reason"] = coverage::LineCollector.unsupported_reason
end

root = File.realpath(Dir.mktmpdir("line-coverage-probe"))
target = File.join(root, "probe_target.rb")
File.write(target, <<~RUBY)
  def probe_target(x)
    if x > 1
      :big
    else
      :small
    end
  end

  def probe_loop(n)
    total = 0
    n.times do |i|
      total += i
    end
    total
  end
RUBY

line_coverage = coverage::LineCoverage.start(root: root, ignored_paths: [])
result["started"] = !line_coverage.nil?
if line_coverage
  require target
  result["tests"] = Array.new(4) do |index|
    test_id = "t#{index}"
    line_coverage.start_test(test_id)
    index.even? ? probe_target(2) : probe_target(0)
    probe_loop(5000) if index >= 2
    GC.start
    _count, packed = line_coverage.finish_test(test_id, [])
    coverage::LineFiles.unpack(packed).transform_values do |bitmap|
      bitmap.bytes.each_with_index.flat_map do |byte, offset|
        (0..7).select { |bit| byte[bit] == 1 }.map { |bit| offset * 8 + bit }
      end
    end
  end
  # t0 and t2 take the branch on line 3, t1 and t3 the one on line 5; t2 and t3 also run the loop.
  loop_lines = (10..15).to_a
  result["known_answer"] = result["tests"] == [
    {"probe_target.rb" => [1, 2, 3, 7, 9]},
    {"probe_target.rb" => [1, 2, 5, 7, 9]},
    {"probe_target.rb" => [1, 2, 3, 7, 9] + loop_lines},
    {"probe_target.rb" => [1, 2, 5, 7, 9] + loop_lines}
  ]
end

File.write(ARGV.fetch(0), JSON.generate(result))
