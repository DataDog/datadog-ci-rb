require_relative "../../../../../lib/datadog/ci/itr/coverage/transport"

RSpec.describe Datadog::CI::ITR::Coverage::Transport do
  subject do
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
    Datadog::CI::ITR::Coverage::Event.new(
      test_id: "1",
      test_suite_id: "2",
      test_session_id: "3",
      coverage: {"file.rb" => true}
    )
  end

  describe "#send_events" do
    context "with a single event" do
      it "sends correct payload" do
        subject.send_events([event])

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
    end

    context "multiple events" do
      let(:events) do
        [
          event,
          Datadog::CI::ITR::Coverage::Event.new(
            test_id: "4",
            test_suite_id: "5",
            test_session_id: "6",
            coverage: {"file.rb" => true, "file2.rb" => true}
          )
        ]
      end
      it "sends all events" do
        subject.send_events(events)

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

      context "when some events are invalid" do
        let(:events) do
          [
            event,
            Datadog::CI::ITR::Coverage::Event.new(
              test_id: "4",
              test_suite_id: nil,
              test_session_id: "6",
              coverage: {"file.rb" => true, "file2.rb" => true}
            )
          ]
        end

        it "filters out invalid events" do
          subject.send_events(events)

          expect(api).to have_received(:citestcov_request) do |args|
            payload = MessagePack.unpack(args[:payload])

            events = payload["coverages"]
            expect(events.count).to eq(1)
          end
        end

        it "logs warning that events were filtered out" do
          subject.send_events(events)

          expect(Datadog.logger).to have_received(:warn).with(
            "citestcov event is invalid: [test_suite_id] is nil. " \
            "Event: Coverage::Event[test_id=4, test_suite_id=, test_session_id=6, " \
            "coverage={\"file.rb\"=>true, \"file2.rb\"=>true}]"
          )
        end
      end

      context "when chunking is used" do
        # one coverage event is approximately 75 bytes
        let(:max_payload_size) { 100 }

        it "filters out invalid events" do
          responses = subject.send_events(events)

          expect(api).to have_received(:citestcov_request).twice
          expect(responses.count).to eq(2)
        end
      end

      context "when max_payload-size is too small" do
        let(:max_payload_size) { 1 }

        it "does not send events that are larger than max size" do
          subject.send_events(events)

          expect(api).not_to have_received(:citestcov_request)
        end
      end
    end

    context "when all events are invalid" do
      let(:events) do
        [
          Datadog::CI::ITR::Coverage::Event.new(
            test_id: "4",
            test_suite_id: "5",
            test_session_id: nil,
            coverage: {"file.rb" => true, "file2.rb" => true}
          ),
          Datadog::CI::ITR::Coverage::Event.new(
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
