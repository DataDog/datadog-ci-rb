desc "Check component architecture boundaries"
task :archspec do
  if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.2.0")
    abort "ArchSpec requires Ruby 3.2 or newer"
  end

  sh "bundle exec archspec check --config spec/architecture/Archspec.rb"
end
