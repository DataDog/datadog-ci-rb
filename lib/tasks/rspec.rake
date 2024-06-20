namespace :datadog do
  namespace :ci do
    namespace :rspec do
      task :skippable_percentage do
        require "rspec/core"
        require "datadog/ci"

        Datadog.configure do |c|
          c.ci.enabled = true
          # disabling ITR makes no sense for this task
          c.ci.itr_enabled = true

          c.ci.instrument :rspec, dry_run_enabled: true
        end

        rspec_cli_options = %w[
          --dry-run
          spec
        ]
        options = ::RSpec::Core::ConfigurationOptions.new(rspec_cli_options)
        exit_code = ::RSpec::Core::Runner.new(options).run($stderr, $stdout)

        if exit_code != 0
          Datadog.logger.error("RSpec dry-run failed with exit code #{exit_code}")
        end

        itr = Datadog.send(:components).itr
        puts "Skippable percentage: #{itr.skipped_tests_count.to_f / itr.total_tests_count}"
      end
    end
  end
end
