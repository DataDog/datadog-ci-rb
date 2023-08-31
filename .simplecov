SimpleCov.enable_coverage :branch if RUBY_VERSION >= "2.5.0"

SimpleCov.add_filter %r{/vendor/}
SimpleCov.add_filter %r{/spec/support/}

SimpleCov.coverage_dir ENV.fetch("COVERAGE_DIR", "coverage")

# Each test run requires its own unique command_name.
# When running `rake spec:test_name`, the test process doesn"t have access to the
# rake task process, so we have come up with unique values ourselves.
#
# The current approach is to combine the ruby engine (ruby-2.7,jruby-9.2),
# program name (rspec/test), command line arguments (--pattern spec/**/*_spec.rb),
# and the loaded gemset.
#
# This should allow us to distinguish between runs with the same tests, but different gemsets:
#   * appraisal ruby-3.2.0-rspec-3 rake spec:rspec
#   * appraisal ruby-3.2.0-minitest-5 rake spec:minitest
#
# Subsequent runs of the same exact test suite should have the same command_name.
command_line_arguments = ARGV.join(" ")
gemset_hash = Digest::MD5.hexdigest Gem.loaded_specs.values.map { |x| "#{x.name}#{x.version}" }.sort.join
ruby_engine = "#{RUBY_ENGINE}-#{RUBY_ENGINE_VERSION}"

SimpleCov.command_name "#{ruby_engine}:#{gemset_hash}:#{$PROGRAM_NAME} #{command_line_arguments}"
