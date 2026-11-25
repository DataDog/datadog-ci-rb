# frozen_string_literal: true

require "stringio"

require_relative "../../../../../lib/datadog/ci/test_impact_analysis/coverage/files"

RSpec.describe Datadog::CI::TestImpactAnalysis::Coverage::Files do
  context "when a test replaced File, as FakeFS does" do
    let(:root) { Datadog::CI::Git::LocalRepository.root }
    let(:custom_impacted_files) { ["#{root}/docs/b.md", "docs/a.md"] }

    before do
      custom_impacted_files
      stub_const("File", Class.new(StringIO))
    end

    it "still makes custom impacted files repository-relative" do
      files = described_class.new({}, custom_impacted_files)

      expect(files.to_enum(:each).to_a).to eq(["docs/b.md", "docs/a.md"])
      expect(files.size).to eq(2)
    end
  end
end
