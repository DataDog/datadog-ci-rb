namespace :coverage do
  # Generates one global report for all tracer tests
  task :report do
    require "simplecov"

    resultset_files = Dir["#{ENV.fetch("COVERAGE_DIR", "coverage")}/.resultset.json"] +
      Dir["#{ENV.fetch("COVERAGE_DIR", "coverage")}/versions/**/.resultset.json"]

    SimpleCov.collate resultset_files do
      coverage_dir "#{ENV.fetch("COVERAGE_DIR", "coverage")}/report"
      if ENV["CI"] == "true"
        require "simplecov-cobertura"
        formatter SimpleCov::Formatter::MultiFormatter.new(
          [SimpleCov::Formatter::HTMLFormatter,
            SimpleCov::Formatter::CoberturaFormatter] # Used by codecov
        )
      else
        formatter SimpleCov::Formatter::HTMLFormatter
      end
    end
  end

  # Generates one report for each Ruby version
  task :report_per_ruby_version do
    require "simplecov"

    versions = Dir["#{ENV.fetch("COVERAGE_DIR", "coverage")}/versions/*"]
      # do not include jruby coverage for now
      # see https://github.com/simplecov-ruby/simplecov/pull/972
      .filter { |version| !version.include?("jruby") }
      .map { |f| File.basename(f) }

    versions.map do |version|
      puts "Generating report for: #{version}"
      SimpleCov.collate Dir["#{ENV.fetch("COVERAGE_DIR", "coverage")}/versions/#{version}/**/.resultset.json"] do
        coverage_dir "#{ENV.fetch("COVERAGE_DIR", "coverage")}/report/versions/#{version}"
        formatter SimpleCov::Formatter::HTMLFormatter
      end
    end
  end
end
