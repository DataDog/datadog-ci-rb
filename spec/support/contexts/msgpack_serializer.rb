# "msgpack serializer" shared context uses serializer defined in `subject`
# to serialize the data and then unpacks it to JSON.

RSpec.shared_context "msgpack serializer" do
  subject {}

  let(:msgpack_jsons) do
    if subject.is_a?(Array)
      subject.map { |s| MessagePack.unpack(MessagePack.pack(s)) }
    else
      [MessagePack.unpack(MessagePack.pack(subject))]
    end
  end

  let(:msgpack_json) { msgpack_jsons.first }
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
