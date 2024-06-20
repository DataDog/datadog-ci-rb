# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in datadog-ci.gemspec
gemspec

# dev experience
gem "pry"
gem "rake"
gem "standard", "~> 1.31"

# native extensions
gem "rake-compiler"

# testing
gem "rspec"
gem "rspec-collection_matchers"
gem "rspec_junit_formatter"
gem "climate_control"
gem "appraisal"
gem "webmock"
# platform helpers
gem "os"

# docs and release
gem "yard"
gem "redcarpet" if RUBY_PLATFORM != "java"
gem "webrick"
gem "pimpmychangelog", ">= 0.1.2"

# coverage
gem "simplecov"
gem "simplecov-cobertura", "~> 2.1.0"

# type checking
group :check do
  if RUBY_VERSION >= "3.0.0" && RUBY_PLATFORM != "java"
    gem "rbs", "~> 3.5.0", require: false
    gem "steep", "~> 1.7.0", require: false
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
