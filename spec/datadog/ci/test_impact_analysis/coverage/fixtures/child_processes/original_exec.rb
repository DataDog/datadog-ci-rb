# frozen_string_literal: true

# Run by child_processes_spec.rb: runs its arguments with Bundler's original environment, as
# puma does when it restarts.
require "bundler"
Bundler.with_original_env { exec(*ARGV) }
