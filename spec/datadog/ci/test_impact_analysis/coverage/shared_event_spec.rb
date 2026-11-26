# frozen_string_literal: true

require "msgpack"

require_relative "../../../../../lib/datadog/ci/test_impact_analysis/coverage/line_files"
require_relative "../../../../../lib/datadog/ci/test_impact_analysis/coverage/shared_event"

RSpec.describe Datadog::CI::TestImpactAnalysis::Coverage::SharedEvent do
  subject(:event) { described_class.new(test_session_id: "42", part: "unowned", files: files) }

  let(:files) { Datadog::CI::TestImpactAnalysis::Coverage::LineFiles.from_bitmaps("lib/a.rb" => [0b0000_0100].pack("C*")) }

  it "carries the part in place of a span id" do
    expect(MessagePack.unpack(MessagePack.pack(event))).to eq(
      "test_session_id" => 42,
      "shared" => "unowned",
      "files" => [{"filename" => "lib/a.rb", "bitmap" => [0b0000_0100].pack("C*")}]
    )
  end

  it { is_expected.to be_valid }

  it "shows the decoded lines" do
    expect(event.inspect_coverage).to eq("lib/a.rb" => [2])
  end
end
