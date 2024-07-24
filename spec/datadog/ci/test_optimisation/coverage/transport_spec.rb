require_relative "../../../../../lib/datadog/ci/test_optimisation/coverage/transport"

RSpec.describe Datadog::CI::TestOptimisation::Coverage::Transport do
  include_context "Telemetry spy"

  subject(:transport) do
    described_class.new(
      api: api,
      max_payload_size: max_payload_size
    )
  end

  before do
    allow(Datadog.logger).to receive(:warn)
  end

  let(:max_payload_size) { 5 * 1024 * 1024 }
  let(:api) { spy(:api) }

  let(:event) do
    Datadog::CI::TestOptimisation::Coverage::Event.new(
      test_id: "1",
      test_suite_id: "2",
      test_session_id: "3",
      coverage: {"file.rb" => true}
    )
  end

  describe "#send_events" do
    context "with a single event" do
      subject { transport.send_events([event]) }

      it "sends correct payload" do
        subject

        expect(api).to have_received(:citestcov_request) do |args|
          expect(args[:path]).to eq("/api/v2/citestcov")

          payload = MessagePack.unpack(args[:payload])
          expect(payload["version"]).to eq(2)

          events = payload["coverages"]
          expect(events.count).to eq(1)
          expect(events.first["span_id"]).to eq(event.test_id.to_i)
          expect(events.first["test_suite_id"]).to eq(event.test_suite_id.to_i)
          expect(events.first["test_session_id"]).to eq(event.test_session_id.to_i)
          expect(events.first["files"]).to eq([{"filename" => "file.rb"}])
        end
      end

      it_behaves_like "emits telemetry metric", :inc, "events_enqueued_for_serialization", 1
      it_behaves_like "emits telemetry metric", :distribution, "endpoint_payload.events_count", 1

      it "tags event with code_coverage endpoint" do
        subject

        expect(telemetry_metric(:distribution, "endpoint_payload.events_count")).to(
          have_attributes(tags: {"endpoint" => "code_coverage"})
        )
      end
    end

    context "multiple events" do
      subject { transport.send_events(events) }

      let(:events) do
        [
          event,
          Datadog::CI::TestOptimisation::Coverage::Event.new(
            test_id: "4",
            test_suite_id: "5",
            test_session_id: "6",
            coverage: {"file.rb" => true, "file2.rb" => true}
          )
        ]
      end

      it "sends all events" do
        subject

        expect(api).to have_received(:citestcov_request) do |args|
          payload = MessagePack.unpack(args[:payload])
          payload_events = payload["coverages"]
          expect(payload_events.count).to eq(events.count)
          expect(payload_events.map { |e| e["span_id"] }).to eq(events.map(&:test_id).map(&:to_i))
          expect(payload_events.map { |e| e["files"] }).to eq(
            [
              [{"filename" => "file.rb"}],
              [{"filename" => "file.rb"}, {"filename" => "file2.rb"}]
            ]
          )
        end
      end

      it_behaves_like "emits telemetry metric", :inc, "events_enqueued_for_serialization", 2
      it_behaves_like "emits telemetry metric", :distribution, "endpoint_payload.events_count", 2

      context "when some events are invalid" do
        let(:events) do
          [
            event,
            Datadog::CI::TestOptimisation::Coverage::Event.new(
              test_id: "4",
              test_suite_id: nil,
              test_session_id: "6",
              coverage: {"file.rb" => true, "file2.rb" => true}
            )
          ]
        end

        it "filters out invalid events" do
          subject

          expect(api).to have_received(:citestcov_request) do |args|
            payload = MessagePack.unpack(args[:payload])

            events = payload["coverages"]
            expect(events.count).to eq(1)
          end
        end

        it "logs warning that events were filtered out" do
          subject

          expect(Datadog.logger).to have_received(:warn).with(
            "citestcov event is invalid: [test_suite_id] is nil. " \
            "Event: Coverage::Event[test_id=4, test_suite_id=, test_session_id=6, " \
            "coverage={\"file.rb\"=>true, \"file2.rb\"=>true}]"
          )
        end

        it_behaves_like "emits telemetry metric", :inc, "events_enqueued_for_serialization", 1
        it_behaves_like "emits telemetry metric", :distribution, "endpoint_payload.events_count", 1
      end

      context "when chunking is used" do
        # one coverage event is approximately 75 bytes
        let(:max_payload_size) { 100 }

        it "splits events based on size" do
          responses = subject

          expect(api).to have_received(:citestcov_request).twice
          expect(responses.count).to eq(2)
        end

        it_behaves_like "emits telemetry metric", :inc, "events_enqueued_for_serialization", 2
        it_behaves_like "emits telemetry metric", :distribution, "endpoint_payload.events_count", 1
      end

      context "when max_payload-size is too small" do
        let(:max_payload_size) { 1 }

        it "does not send events that are larger than max size" do
          subject

          expect(api).not_to have_received(:citestcov_request)
        end
      end
    end

    context "when all events are invalid" do
      let(:events) do
        [
          Datadog::CI::TestOptimisation::Coverage::Event.new(
            test_id: "4",
            test_suite_id: "5",
            test_session_id: nil,
            coverage: {"file.rb" => true, "file2.rb" => true}
          ),
          Datadog::CI::TestOptimisation::Coverage::Event.new(
            test_id: "8",
            test_suite_id: nil,
            test_session_id: "6",
            coverage: {"file.rb" => true, "file2.rb" => true}
          )
        ]
      end

      it "does not send anything" do
        subject.send_events(events)

        expect(api).not_to have_received(:citestcov_request)
      end
    end
  end
end
