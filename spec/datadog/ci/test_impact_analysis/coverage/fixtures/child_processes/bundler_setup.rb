# Stands in for bundler/setup, which RubyGems loads while it starts when BUNDLER_SETUP
# names it. Like Bundler.setup evaluating a gemspec, it runs repository code.
require_relative "manifest"
child_processes_manifest
