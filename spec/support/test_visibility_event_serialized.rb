RSpec.shared_context "Test visibility event serialized" do
  subject {}

  let(:msgpack_json) { MessagePack.unpack(MessagePack.pack(subject)) }
  let(:content) { msgpack_json["content"] }
  let(:meta) { content["meta"] }
  let(:metrics) { content["metrics"] }

  def expect_event_header(version: 1, type: "test")
    expect(msgpack_json).to include(
      {
        "version" => version,
        "type" => type
      }
    )
  end
end
