# frozen_string_literal: true

# Loaded through RUBYOPT into the processes that a test starts (see ChildProcesses), so
# that the lines they run count for that test. It loads only the native line collector,
# opens one context for the whole process and has the collector write the context's lines
# at exit, after the process's exit handlers.
#
# The whole process belongs to that test, so the record holds the context's lines and
# every line the collector keeps outside contexts, such as initialisers (see
# ChildProcesses.decode_record for the format).
#
# It runs in any Ruby such a process uses, so it keeps to syntax that every Ruby parses,
# defines no constant, method or global, and removes the Datadog modules that loading the
# collector created, unless datadog-ci loads after it from RUBYOPT. Any failure leaves the
# process uncovered and otherwise unchanged.
begin
  # The same name as ChildProcesses::ENV_CONTEXT, which this file cannot load.
  dd_ci_line_coverage_prefix = ENV["DD_TEST_OPTIMIZATION_TIA_LINE_COVERAGE_CHILD"]
  dd_ci_line_coverage_config = nil
  if dd_ci_line_coverage_prefix && defined?(RUBY_ENGINE) && RUBY_ENGINE == "ruby"
    dd_ci_line_coverage_config = File.read(File.join(File.dirname(dd_ci_line_coverage_prefix), "config")).split("\n")
  end

  # The parent writes: its Ruby, the path of the native extension it loaded, the
  # repository root, then the ignored paths, one per line.
  if dd_ci_line_coverage_config &&
      dd_ci_line_coverage_config[0] == [RUBY_ENGINE, RUBY_VERSION, RUBY_PATCHLEVEL, RUBY_REVISION, RUBY_PLATFORM].join(" ")
    dd_ci_line_coverage_defined = []
    dd_ci_line_coverage_namespace = Object
    ["Datadog", "CI", "TestImpactAnalysis", "Coverage"].each do |name|
      break unless dd_ci_line_coverage_namespace.const_defined?(name, false)

      dd_ci_line_coverage_namespace = dd_ci_line_coverage_namespace.const_get(name, false)
      dd_ci_line_coverage_defined << name
    end

    require dd_ci_line_coverage_config[1]
    dd_ci_line_collector = Object.const_get("Datadog::CI::TestImpactAnalysis::Coverage::LineCollector")

    # The process may define its own Datadog, or test whether one is defined. Auto
    # instrumentation in RUBYOPT loads datadog-ci after this file, and datadog-ci then finds
    # the extension loaded, so it needs the modules that loading the extension defined.
    dd_ci_line_coverage_created = ["Datadog", "CI", "TestImpactAnalysis", "Coverage"][dd_ci_line_coverage_defined.size]
    dd_ci_line_coverage_libraries = ENV["RUBYOPT"].to_s.scan(/(?:\A|\s)-r\s*(\S+)/).flatten
    dd_ci_line_coverage_rubyopt_loads_datadog_ci = dd_ci_line_coverage_libraries.any? do |dd_ci_line_coverage_library|
      %r{(?:\A|/)datadog/ci/auto_instrument(?:\.rb)?\z} =~ dd_ci_line_coverage_library.to_s
    end
    if dd_ci_line_coverage_created && !dd_ci_line_coverage_rubyopt_loads_datadog_ci
      dd_ci_line_coverage_owner = dd_ci_line_coverage_defined.inject(Object) { |owner, name| owner.const_get(name, false) }
      dd_ci_line_coverage_owner.send(:remove_const, dd_ci_line_coverage_created)
    end

    dd_ci_line_coverage_serial = nil
    if dd_ci_line_collector.supported? &&
        (!defined?(RubyVM::YJIT) || dd_ci_line_collector.yjit_supported?) &&
        dd_ci_line_collector.start(dd_ci_line_coverage_config[2], dd_ci_line_coverage_config.drop(3))
      dd_ci_line_coverage_serial = dd_ci_line_collector.open_context
    end

    if dd_ci_line_coverage_serial
      Fiber[dd_ci_line_collector::CONTEXT_KEY] = dd_ci_line_coverage_serial
      dd_ci_line_collector.write_record_at_exit(dd_ci_line_coverage_prefix, dd_ci_line_coverage_serial, false)
    end
  end
rescue StandardError, ScriptError
  nil
end
