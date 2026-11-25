require "bundler"
Bundler.with_unbundled_env { exec(*ARGV) }
