# frozen_string_literal: true

require "msgpack"

require_relative "../../../../../lib/datadog/ci/test_impact_analysis/coverage/line_files"

RSpec.describe Datadog::CI::TestImpactAnalysis::Coverage::LineFiles do
  subject(:files) { described_class.new(bitmaps, custom_impacted_files) }

  # Lines 1 and 9 of lib/a.rb, line 3 of lib/b.rb.
  let(:bitmaps) do
    {
      "lib/a.rb" => [0b0000_0010, 0b0000_0010].pack("C*"),
      "lib/b.rb" => [0b0000_1000].pack("C*")
    }
  end
  let(:custom_impacted_files) { [] }

  def unpacked
    packer = MessagePack::Packer.new
    files.write_to(packer)
    MessagePack.unpack(packer.to_s)
  end

  it "writes a filename and a binary bitmap for each file with lines" do
    expect(unpacked).to eq(
      [
        {"filename" => "lib/a.rb", "bitmap" => bitmaps["lib/a.rb"]},
        {"filename" => "lib/b.rb", "bitmap" => bitmaps["lib/b.rb"]}
      ]
    )
    expect(unpacked.first.fetch("bitmap").encoding).to eq(Encoding::BINARY)
    expect(files.size).to eq(2)
  end

  context "with custom impacted files" do
    let(:root) { Datadog::CI::Git::LocalRepository.root }
    let(:custom_impacted_files) { ["docs/a.md", File.join(root, "docs/b.md"), "lib/a.rb", ""] }

    it "adds them without lines, repository-relative, once per file" do
      expect(unpacked.drop(2)).to eq([{"filename" => "docs/a.md"}, {"filename" => "docs/b.md"}])
      expect(files.size).to eq(4)
      expect(files.to_enum(:each).to_a).to eq(["lib/a.rb", "lib/b.rb", "docs/a.md", "docs/b.md"])
    end
  end

  describe "#inspect_coverage" do
    let(:custom_impacted_files) { ["docs/a.md"] }

    it "decodes the line numbers" do
      expect(files.inspect_coverage).to eq("lib/a.rb" => [1, 9], "lib/b.rb" => [3], "docs/a.md" => true)
    end
  end
end
