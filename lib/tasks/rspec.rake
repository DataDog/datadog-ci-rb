namespace :datadog do
  namespace :ci do
    namespace :rspec do
      task :skippable_percentage do
        require "datadog/ci/test_optimisation/skippable_percentage"

        percentage_skipped = Datadog::CI::TestOptimisation::SkippablePercentage.new(rspec_cli_options: []).calculate
        print(percentage_skipped)
      end

      task :skippable_percentage_estimate do
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

        test_optimisation = Datadog.send(:components).test_optimisation

        skippable_tests_count = test_optimisation.skippable_tests.count
        estimated_tests_count = Dir["spec/**/*_spec.rb"].map { |path| File.read(path) }.join.scan(/(  it)|(  scenario)/).count

        result = [(skippable_tests_count.to_f / estimated_tests_count).floor(2), 0.99].min
        print(result)
      end
    end
  end
end
