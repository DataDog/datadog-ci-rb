# frozen_string_literal: true

require "spec_helper"
require "datadog/ci/source_code/static_dependencies"
require "open3"
require "rbconfig"

RSpec.describe Datadog::CI::SourceCode::ISeqCollector do
  let(:lib_path) { File.expand_path("../../../../lib", __dir__) }

  describe "debug gem compatibility", skip: !described_class::STATIC_DEPENDENCIES_EXTRACTION_AVAILABLE do
    it "allows debug to install ObjectSpace.each_iseq after datadog/ci is loaded first" do
      skip "reproduces only on Linux" unless RUBY_PLATFORM.include?("linux")

      script = <<~RUBY
        require "datadog/ci"
        require "debug"

        abort "ObjectSpace.each_iseq is missing" unless ObjectSpace.respond_to?(:each_iseq)
      RUBY

      stdout, stderr, status = Open3.capture3(
        {"RUBYOPT" => nil},
        RbConfig.ruby,
        "-rbundler/setup",
        "-I#{lib_path}",
        "-e",
        script
      )

      expect(status).to be_success, "stdout:\n#{stdout}\nstderr:\n#{stderr}"
    end
  end
end
