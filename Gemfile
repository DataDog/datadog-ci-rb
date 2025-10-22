# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in datadog-ci.gemspec
gemspec

# debugging
gem "debug" if RUBY_PLATFORM != "java"

# native extensions
gem "rake-compiler"

# coverage
gem "simplecov"

# build&test
gem "rspec"
gem "rspec-collection_matchers"
gem "rspec_junit_formatter"
gem "appraisal"
gem "climate_control"
gem "webmock"
gem "rake"
gem "yard"
gem "ostruct" # for RSpec instrumentation spec

# test against gem datadog from master
gem "datadog", git: "https://github.com/DataDog/dd-trace-rb.git", branch: "master"

# platform helpers
gem "os"

# type checks, memory checks, etc.
group :check do
  # style
  gem "standard", "~> 1.31"

  # type checks
  if RUBY_VERSION >= "3.4.0" && RUBY_PLATFORM != "java"
    gem "rbs", "~> 3.9.0", require: false
    gem "steep", "~> 1.10.0", require: false
  end

  # memory checks
  gem "ruby_memcheck", ">= 3" if RUBY_VERSION >= "3.4.0" && RUBY_PLATFORM != "java"
end

# development dependencies for vscode integration and debugging
group :development do
  if RUBY_VERSION >= "3.0.0" && RUBY_PLATFORM != "java"
    # vscode integration
    gem "ruby-lsp"
    gem "ruby-lsp-rspec"
  end

  # docs and release
  gem "redcarpet" if RUBY_PLATFORM != "java"
  gem "webrick"
  gem "pimpmychangelog", ">= 0.1.2"

  # irb is updated earlier that way
  gem "irb" if RUBY_PLATFORM != "java"
end
