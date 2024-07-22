namespace :datadog do
  namespace :ci do
    namespace :rspec do
      task skippable_percentage: :environment do
        require "rspec/core"
        require "datadog/ci"

        Datadog.configure do |c|
          c.ci.enabled = true
          c.ci.itr_enabled = true
          c.ci.discard_traces = true
          c.ci.instrument :rspec, dry_run_enabled: true
          c.tracing.enabled = true
        end

        rspec_cli_options = %w[
          --dry-run
          spec
        ]
        options = ::RSpec::Core::ConfigurationOptions.new(rspec_cli_options)
        devnull = File.new("/dev/null", "w")
        exit_code = ::RSpec::Core::Runner.new(options).run(devnull, devnull)

        if exit_code != 0
          Datadog.logger.error("RSpec dry-run failed with exit code #{exit_code}")
        end

        itr = Datadog.send(:components).itr
        print((itr.skipped_tests_count.to_f / itr.total_tests_count).floor(2))
      end

      task skippable_percentage_estimate: :environment do
        require "datadog/ci"

        if ENV["DD_SERVICE"].nil?
          Datadog.logger.error("DD_SERVICE is not set. You must provide it to estimate the skippable percentage.")
          exit 1
        end

        Datadog.configure do |c|
          c.ci.enabled = true
          c.ci.itr_enabled = true
          c.ci.discard_traces = true
          c.tracing.enabled = true
        end

        test_session = Datadog::CI.start_test_session
        test_session&.finish

        itr = Datadog.send(:components).itr

        skippable_tests_count = itr.skippable_tests.count
        estimated_tests_count = Dir["spec/**/*_spec.rb"].map { |path| File.read(path) }.join.scan(/(  it)|(  scenario)/).count

        result = [(skippable_tests_count.to_f / estimated_tests_count).floor(2), 0.99].min
        print(result)
      end
    end
  end
end
