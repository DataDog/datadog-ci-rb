# frozen_string_literal: true

# RubyGems requires "rubygems/defaults/<RUBY_ENGINE>" while it starts, before it loads
# Bundler for `bundle exec` (BUNDLER_SETUP) and before Ruby loads the libraries that
# RUBYOPT names. ChildProcesses puts this file's directory first in the RUBYLIB of the
# processes that a test starts, so the child bootstrap runs before Bundler.setup, which
# evaluates gemspecs that may run repository code.
#
# The directory leaves the load path at once, so the process loads every other file as
# it would without it; RUBYLIB keeps it for the process's own children. The bootstrap is
# the one that RUBYOPT names, and loads once.
begin
  dd_ci_line_coverage_hook_directory = File.expand_path("../..", File.dirname(__FILE__))
  $LOAD_PATH.reject! do |dd_ci_line_coverage_entry|
    File.expand_path(dd_ci_line_coverage_entry) == dd_ci_line_coverage_hook_directory
  end
  require File.expand_path("../child_bootstrap.rb", dd_ci_line_coverage_hook_directory)
rescue StandardError, ScriptError
  nil
end

# CRuby ships no file of this name. One that the directory hid loads as RubyGems would
# have loaded it, errors included.
dd_ci_line_coverage_hidden_file = begin
  dd_ci_line_coverage_this_file = File.expand_path(__FILE__)
  $LOAD_PATH.map do |dd_ci_line_coverage_entry|
    File.expand_path("rubygems/defaults/ruby.rb", dd_ci_line_coverage_entry)
  end.find do |dd_ci_line_coverage_path|
    dd_ci_line_coverage_path != dd_ci_line_coverage_this_file && File.file?(dd_ci_line_coverage_path)
  end
rescue
  nil
end
require dd_ci_line_coverage_hidden_file if dd_ci_line_coverage_hidden_file
