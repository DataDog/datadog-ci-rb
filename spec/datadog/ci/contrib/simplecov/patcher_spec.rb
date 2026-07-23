# frozen_string_literal: true

require_relative "../../../../../lib/datadog/ci/contrib/simplecov/patcher"

RSpec.describe Datadog::CI::Contrib::Simplecov::Patcher do
  describe ".patch" do
    before do
      described_class.patch
    end

    it "installs the result extractor on the loaded SimpleCov version" do
      expect(SimpleCov.method(:__dd_peek_result).owner)
        .to eq(Datadog::CI::Contrib::Simplecov::ResultExtractor::ClassMethods)
    end

    it "installs the report uploader around the loaded SimpleCov hook" do
      hook = SimpleCov.method(:process_results_and_report_error)

      expect(hook.owner).to eq(Datadog::CI::Contrib::Simplecov::ReportUploader::ClassMethods)
      expect(hook.super_method).not_to be_nil
    end
  end
end
