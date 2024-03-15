# frozen_string_literal: true

require_relative "lib/datadog/ci/version"

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "yard"
require "rake/extensiontask"

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

TEST_METADATA = {
  "main" => {
    "" => "✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby"
  },
  "cucumber" => {
    "cucumber-3" => "✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby",
    "cucumber-4" => "✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby",
    "cucumber-5" => "✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby",
    "cucumber-6" => "✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby",
    "cucumber-7" => "✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby",
    "cucumber-8" => "✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby",
    "cucumber-9" => "✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby"
  },
  "rspec" => {
    "rspec-3" => "✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby"
  },
  "minitest" => {
    "minitest-5" => "✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby"
  },
  "activesupport" => {
    "activesupport-4" => "✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby",
    "activesupport-5" => "✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby",
    "activesupport-6" => "✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby",
    "activesupport-7" => "✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby"
  },
  "ci_queue_minitest" => {
    "ci-queue-0-minitest-5" => "✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby"
  },
  "ci_queue_rspec" => {
    "ci-queue-0-rspec-3" => "✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby"
  },
  "minitest_shoulda_context" => {
    "minitest-5-shoulda-context-2-shoulda-matchers-6" => "❌ 2.7 / ❌ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby"
  }
}

namespace :test do
  task all: TEST_METADATA.map { |k, _| "test:#{k}" }

  ruby_version = RUBY_VERSION[0..2]
  major, minor, = Gem::Version.new(RUBY_ENGINE_VERSION).segments

  ruby_runtime = "#{RUBY_ENGINE}-#{major}.#{minor}"

  TEST_METADATA.each do |key, spec_metadata|
    spec_task = "spec:#{key}"

    desc "Run #{spec_task} tests"
    task key, [:task_args] do |_, args|
      spec_arguments = args.task_args

      appraisals = spec_metadata.select do |_, rubies|
        if RUBY_PLATFORM == "java"
          rubies.include?("✅ #{ruby_version}") && rubies.include?("✅ jruby")
        else
          rubies.include?("✅ #{ruby_version}")
        end
      end

      appraisals.each do |appraisal_group, _|
        command = if appraisal_group.empty?
          "bundle exec rake #{spec_task}"
        else
          "bundle exec appraisal #{ruby_runtime}-#{appraisal_group} rake #{spec_task}"
        end

        command += "'[#{spec_arguments}]'" if spec_arguments

        total_executors = ENV.key?("CIRCLE_NODE_TOTAL") ? ENV["CIRCLE_NODE_TOTAL"].to_i : nil
        current_executor = ENV.key?("CIRCLE_NODE_INDEX") ? ENV["CIRCLE_NODE_INDEX"].to_i : nil

        if total_executors && current_executor && total_executors > 1
          @execution_count ||= 0
          @execution_count += 1
          sh(command) if @execution_count % total_executors == current_executor
        else
          sh(command)
        end
      end
    end
  end
end

namespace :spec do
  desc "" # "Explicitly hiding from `rake -T`"
  RSpec::Core::RakeTask.new(:main) do |t, args|
    t.pattern = "spec/**/*_spec.rb"
    t.exclude_pattern = "spec/**/{contrib}/**/*_spec.rb,"
    if RUBY_ENGINE == "jruby"
      t.exclude_pattern += "spec/**/cov_spec.rb"
    end
    t.rspec_opts = args.to_a.join(" ")
  end

  # Datadog CI integrations
  [
    :cucumber,
    :rspec,
    :minitest,
    :minitest_shoulda_context,
    :activesupport,
    :ci_queue_minitest,
    :ci_queue_rspec
  ].each do |contrib|
    desc "" # "Explicitly hiding from `rake -T`"
    RSpec::Core::RakeTask.new(contrib) do |t, args|
      t.pattern = "spec/datadog/ci/contrib/#{contrib}/**/*_spec.rb"
      t.rspec_opts = args.to_a.join(" ")
    end
  end
end

desc "CI task; it runs all tests for current version of Ruby"
task ci: "test:all"

# native extensions
Rake::ExtensionTask.new("datadog_cov.#{RUBY_VERSION}_#{RUBY_PLATFORM}") do |ext|
  ext.ext_dir = "ext/datadog_cov"
end

task :compile_ext do
  if RUBY_ENGINE == "ruby"
    Rake::Task[:clean].invoke
    Rake::Task[:compile].invoke
  end
end

# run compile before any tests are run
Rake::Task["test:all"].prerequisite_tasks.each { |t| t.enhance([:compile_ext]) }
