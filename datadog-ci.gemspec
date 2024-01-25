# frozen_string_literal: true

require_relative "lib/datadog/ci/version"

Gem::Specification.new do |spec|
  spec.name = "datadog-ci"
  spec.version = Datadog::CI::VERSION::STRING
  spec.required_ruby_version = [
    ">= #{Datadog::CI::VERSION::MINIMUM_RUBY_VERSION}",
    "< #{Datadog::CI::VERSION::MAXIMUM_RUBY_VERSION}"
  ]
  spec.required_rubygems_version = ">= 2.0.0"
  spec.authors = ["Datadog, Inc."]
  spec.email = ["dev@datadoghq.com"]

  spec.summary = "Datadog CI visibility for your ruby application"
  spec.description = <<-DESC
  datadog-ci is a Datadog's CI visibility library for Ruby. It traces
  tests as they are being executed and brings developers visibility into
  their CI pipelines.
  DESC

  spec.homepage = "https://github.com/DataDog/datadog-ci-rb"
  spec.license = "BSD-3-Clause"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["changelog_uri"] = "https://github.com/DataDog/datadog-ci-rb/blob/main/CHANGELOG.md"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/DataDog/datadog-ci-rb"

  spec.files =
    Dir[*%w[
      CHANGELOG.md
      LICENSE*
      NOTICE
      README.md
      lib/**/*
    ]].select { |fn| File.file?(fn) } # We don't want directories, only files

  spec.require_paths = ["lib"]

  spec.add_dependency "msgpack"
end
