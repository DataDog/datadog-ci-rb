# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in datadog-ci.gemspec
gemspec

# needed to run tests, always present at runtime
gem "ddtrace"

gem "pry"
gem "rake"
gem "os"

gem "climate_control"

gem "rspec"
gem "rspec-collection_matchers"
gem "rspec_junit_formatter"
gem "appraisal"
gem "timecop"

gem "standard", "~> 1.31"

gem "yard"
gem "webrick"
gem "pimpmychangelog", ">= 0.1.2"

gem "simplecov"
gem "simplecov-cobertura", "~> 2.1.0"

# type checking
group :check do
  if RUBY_VERSION >= "3.0.0" && RUBY_PLATFORM != "java"
    gem "rbs", "~> 3.2.0", require: false
    gem "steep", "~> 1.6.0", require: false
  end
end

# development dependencies for vscode integration and debugging
group :development do
  if RUBY_VERSION >= "3.0.0" && RUBY_PLATFORM != "java"
    gem "ruby-lsp"
    gem "ruby-lsp-rspec"

    gem "debug"

    gem "irb"
  end
end
