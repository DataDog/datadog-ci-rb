# frozen_string_literal: true

require_relative "changed_lines_target"

abort "Usage: ruby spec/support/fuzz/replay.rb FILE [FILE ...]" if ARGV.empty?
ARGV.each do |path|
  ChangedLinesTarget.check(File.binread(path))
  puts "Passed: #{path}"
end
