# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "datadog/ci/version"
require "yard"

RSpec::Core::RakeTask.new(:spec)

Dir.glob("tasks/*.rake").each { |r| import r }

YARD::Rake::YardocTask.new(:docs) do |t|
  # Options defined in `.yardopts` are read first, then merged with
  # options defined here.
  #
  # It's recommended to define options in `.yardopts` instead of here,
  # as `.yardopts` can be read by external YARD tools, like the
  # hot-reload YARD server `yard server --reload`.

  t.options += ["--title", "datadog-ci #{Datadog::CI::VERSION} documentation"]
end

desc "Run RSpec"
# rubocop:disable Metrics/BlockLength
namespace :spec do
  task all: [:main, :cucumber, :rspec]

  RSpec::Core::RakeTask.new(:main) do |t, args|
    t.pattern = "spec/**/*_spec.rb"
    t.exclude_pattern = "spec/**/{contrib}/**/*_spec.rb,"
    t.rspec_opts = args.to_a.join(" ")
  end

  # Datadog CI integrations
  [
    :cucumber,
    :rspec,
    :minitest
  ].each do |contrib|
    RSpec::Core::RakeTask.new(contrib) do |t, args|
      t.pattern = "spec/datadog/ci/contrib/#{contrib}/**/*_spec.rb"
      t.rspec_opts = args.to_a.join(" ")
    end
  end
end

# Declare a command for execution.
# Jobs are parallelized if running in CI.
def declare(rubies_to_command)
  rubies, command = rubies_to_command.first

  return unless rubies.include?("✅ #{RUBY_VERSION[0..2]}")
  return if RUBY_PLATFORM == "java" && rubies.include?("❌ jruby")

  total_executors = ENV.key?("CIRCLE_NODE_TOTAL") ? ENV["CIRCLE_NODE_TOTAL"].to_i : nil
  current_executor = ENV.key?("CIRCLE_NODE_INDEX") ? ENV["CIRCLE_NODE_INDEX"].to_i : nil

  ruby_runtime = if defined?(RUBY_ENGINE_VERSION)
    "#{RUBY_ENGINE}-#{RUBY_ENGINE_VERSION}"
  else
    "#{RUBY_ENGINE}-#{RUBY_VERSION}" # For Ruby < 2.3
  end

  command = command.sub(/^bundle exec appraisal /, "bundle exec appraisal #{ruby_runtime}-")

  if total_executors && current_executor && total_executors > 1
    @execution_count ||= 0
    @execution_count += 1
    sh(command) if @execution_count % total_executors == current_executor
  else
    sh(command)
  end
end

# | Cucumber | Ruby required |
# |----------|---------------|
# | 3.x      |   2.2+        |
# | 4.x      |   2.3+        |
# | 5.x      |   2.5+        |
# | 6.x      |   2.5+        |
# | 7.x      |   2.5+        |
# | 8.x      |   2.6+        |

desc "CI task; it runs all tests for current version of Ruby"
task :ci do
  declare "✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby" => "bundle exec rake spec:main"

  # RSpec
  declare "✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby" => "bundle exec appraisal rspec-3 rake spec:rspec"

  # Cucumber
  declare "❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby" => "bundle exec appraisal cucumber-3 rake spec:cucumber"
  declare "❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby" => "bundle exec appraisal cucumber-4 rake spec:cucumber"
  declare "❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby" => "bundle exec appraisal cucumber-5 rake spec:cucumber"
  declare "❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby" => "bundle exec appraisal cucumber-6 rake spec:cucumber"
  declare "❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby" => "bundle exec appraisal cucumber-7 rake spec:cucumber"
  declare "❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ❌ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby" => "bundle exec appraisal cucumber-8 rake spec:cucumber"

  # Minitest
  declare "❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby" => "bundle exec appraisal minitest-5 rake spec:minitest"
end
