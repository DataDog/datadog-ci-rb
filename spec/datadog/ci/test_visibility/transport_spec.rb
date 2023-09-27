require_relative "../../../../lib/datadog/ci/test_visibility/transport"

RSpec.describe Datadog::CI::TestVisibility::Transport do
  include_context "CI mode activated" do
    let(:integration_name) { :rspec }
  end

  subject { described_class.new(api_key: api_key, site: site, serializer: serializer) }

  let(:api_key) { "api_key" }
  let(:site) { "datad0ghq.com" }
  let(:serializer) { Datadog::CI::TestVisibility::Serializers }

  let(:http) { spy(:http) }

  before do
    expect(Datadog::CI::Transport::HTTP).to receive(:new).with(
      host: "citestcycle-intake.datad0ghq.com",
      port: 443
    ).and_return(http)
  end

  describe "#send_traces" do
    context "with a single trace and a single span" do
      before do
        produce_test_trace
      end

      it "sends correct payload" do
        subject.send_traces([trace])

        expect(http).to have_received(:request) do |args|
          expect(args[:path]).to eq("/api/v2/citestcycle")
          expect(args[:headers]).to eq({
            "DD-API-KEY" => "api_key",
            "Content-Type" => "application/msgpack"
          })

          payload = MessagePack.unpack(args[:payload])
          expect(payload["version"]).to eq(1)

          metadata = payload["metadata"]["*"]
          expect(metadata).to include("runtime-id", "language", "library_version")

          events = payload["events"]
          expect(events.count).to eq(1)
          expect(events.first["content"]["resource"]).to include("calculator_tests")
        end
      end
    end

    context "multiple traces with 2 spans each" do
      let(:traces_count) { 2 }
      let(:expected_events_count) { 4 }

      before do
        2.times { produce_test_trace(with_http_span: true) }
      end

      it "sends event for each of spans" do
        subject.send_traces(traces)

        expect(http).to have_received(:request) do |args|
          payload = MessagePack.unpack(args[:payload])
          events = payload["events"]
          expect(events.count).to eq(expected_events_count)
        end
      end

      context "when some spans are broken" do
        let(:expected_events_count) { 3 }

        before do
          http_span = spans.find { |span| span.type == "http" }
          http_span.start_time = Time.at(0)
        end

        it "filters out invalid events" do
          subject.send_traces(traces)

          expect(http).to have_received(:request) do |args|
            payload = MessagePack.unpack(args[:payload])

            events = payload["events"]
            expect(events.count).to eq(expected_events_count)

            p events
            span_events = events.filter { |e| e["type"] == "span" }
            expect(span_events.count).to eq(1)
          end
        end
      end
    end

    context "when there are no events" do
      it "does not send anything" do
        subject.send_traces([])

        expect(http).not_to have_received(:request)
      end
    end
  end
end
