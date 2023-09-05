# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in datadog-ci.gemspec
gemspec

# build tasks, utils
gem "rake"
gem "os"

# testing
gem "rspec"
gem "rspec-collection_matchers"
gem "rspec_junit_formatter"
gem "climate_control"
# dependency management for tests
gem "appraisal"
# code coverage
gem "simplecov"
gem "simplecov-cobertura", "~> 2.1.0"

# ruby linting and formatting
gem "standard", "~> 1.31.0"

# docs
gem "yard"
gem "webrick"

# debug
gem "debug", ">= 1.0.0" if RUBY_PLATFORM != "java"
gem "pry"

# type checking
group :check do
  if RUBY_PLATFORM != "java"
    gem "rbs", "~> 3.1.0", require: false
    gem "steep", "~> 1.4.0", require: false
  end
end
