# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in datadog-ci.gemspec
gemspec

gem "pry"
gem "rake"
gem "rspec"
gem "os"

if RUBY_VERSION >= "2.5"
  gem "climate_control"
else
  gem "climate_control", "~> 0.2.0"
end

gem "rspec-collection_matchers"
gem "rspec_junit_formatter"
gem "appraisal"
gem "standard", "<= 1.24.3" if RUBY_VERSION >= "2.2.0"

gem "yard"
gem "webrick"
