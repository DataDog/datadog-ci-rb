# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in datadog-ci.gemspec
gemspec

gem "pry"
gem "rake"
gem "rspec"
gem "os"

gem "climate_control"

gem "rspec-collection_matchers"
gem "rspec_junit_formatter"
gem "appraisal"
gem "standard", "~> 1.31.0"

gem "yard"
gem "webrick"

gem "simplecov"
gem "simplecov-cobertura", "~> 2.1.0"

# type checking
group :check do
  if RUBY_PLATFORM != "java"
    gem "rbs", "~> 3.1.0", require: false
    gem "steep", "~> 1.4.0", require: false
  end
end
