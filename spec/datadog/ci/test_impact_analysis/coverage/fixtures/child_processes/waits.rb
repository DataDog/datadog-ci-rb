sleep 0.1 until File.exist?(ARGV.fetch(0))
load File.expand_path("leaf.rb", __dir__)
