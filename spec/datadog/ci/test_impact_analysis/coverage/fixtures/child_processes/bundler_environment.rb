print [ENV["BUNDLER_SETUP"], ENV["DD_TEST_OPTIMIZATION_TIA_LINE_COVERAGE_BUNDLER_SETUP"], defined?(Bundler.setup) ? "Bundler" : nil, respond_to?(:child_processes_manifest, true)].inspect
