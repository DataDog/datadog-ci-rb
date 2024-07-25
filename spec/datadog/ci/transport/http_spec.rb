require_relative "../../../../lib/datadog/ci/transport/http"

RSpec.describe Datadog::CI::Transport::HTTP do
  subject(:transport) { described_class.new(host: host, port: port, **options) }

  let(:host) { "datadog-host" }
  let(:port) { 8132 }
  let(:timeout) { 10 }
  let(:ssl) { true }
  let(:options) { {} }

  shared_context "HTTP adapter stub" do
    let(:adapter) { instance_double(::Datadog::CI::Transport::Adapters::Net) }

    before do
      allow(::Datadog::CI::Transport::Adapters::Net).to receive(:new)
        .with(
          hostname: transport.host,
          port: transport.port,
          timeout_seconds: transport.timeout,
          ssl: transport.ssl
        ).and_return(adapter)
    end
  end

  describe "#initialize" do
    context "given no options" do
      let(:options) { {} }

      it do
        is_expected.to have_attributes(
          host: host,
          port: port,
          timeout: Datadog::CI::Transport::HTTP::DEFAULT_TIMEOUT,
          ssl: true
        )
      end
    end

    context "given a :port option" do
      let(:options) { {timeout: port} }

      it { is_expected.to have_attributes(timeout: port) }
    end

    context "given a :timeout option" do
      let(:options) { {timeout: timeout} }

      it { is_expected.to have_attributes(timeout: timeout) }
    end

    context "given a :ssl option" do
      let(:options) { {ssl: ssl} }

      context "with nil" do
        let(:ssl) { nil }

        it { is_expected.to have_attributes(ssl: true) }
      end

      context "with false" do
        let(:ssl) { false }

        it { is_expected.to have_attributes(ssl: false) }
      end
    end

    context "given a :compress option" do
      let(:options) { {compress: compress} }

      context "with nil" do
        let(:compress) { nil }

        it { is_expected.to have_attributes(compress: false) }
      end

      context "with false" do
        let(:compress) { true }

        it { is_expected.to have_attributes(compress: true) }
      end
    end
  end

  describe "#request" do
    include_context "HTTP adapter stub"

    let(:path) { "/api/v1/intake" }
    let(:payload) { '{ "key": "value" }' }
    let(:headers) { {"Content-Type" => "application/json"} }
    let(:expected_headers) { headers }
    let(:request_options) { {accept_compressed_response: false} }

    let(:response_payload) { "sample payload" }
    let(:net_http_response) { double("Net::HTTP::Response", code: 200, body: response_payload, "[]": nil) }
    let(:http_response) { Datadog::CI::Transport::Adapters::Net::Response.new(net_http_response) }

    subject(:response) { transport.request(path: path, payload: payload, headers: headers, **request_options) }

    context "when request is successful" do
      let(:expected_payload) { payload }
      let(:expected_path) { path }
      let(:expected_headers) { headers }
      let(:expected_verb) { "post" }

      before do
        expect(adapter).to receive(:call).with(
          payload: expected_payload,
          path: expected_path,
          headers: expected_headers,
          verb: expected_verb
        ).and_return(http_response)
      end

      it "produces a response" do
        is_expected.to be_a_kind_of(Datadog::CI::Transport::Adapters::Net::Response)

        expect(response.code).to eq(200)
        expect(response.payload).to eq("sample payload")
        expect(response.request_compressed).to eq(false)
        expect(response.request_size).to eq(payload.size)
      end

      context "when accepting gzipped response" do
        let(:expected_headers) { {"Content-Type" => "application/json", "Accept-Encoding" => "gzip"} }
        let(:request_options) { {accept_compressed_response: true} }

        it { is_expected.to be_a_kind_of(Datadog::CI::Transport::Adapters::Net::Response) }
      end
    end

    context "when compressing payload" do
      let(:headers) { {"Content-Type" => "application/json"} }
      let(:expected_headers) { {"Content-Type" => "application/json", "Content-Encoding" => "gzip"} }
      let(:options) { {compress: true} }
      let(:post_request) { double(:post_request) }

      let(:expected_payload) { Datadog::CI::Transport::Gzip.compress(payload) }
      let(:expected_path) { path }
      let(:expected_headers) { headers }
      let(:expected_verb) { "post" }

      before do
        expect(adapter).to receive(:call).with(
          payload: expected_payload,
          path: expected_path,
          headers: expected_headers,
          verb: expected_verb
        ).and_return(http_response)
      end

      it "produces a response" do
        is_expected.to be_a_kind_of(Datadog::CI::Transport::Adapters::Net::Response)

        expect(response.code).to eq(200)
        expect(response.request_compressed).to eq(true)
        expect(response.request_size).to eq(expected_payload.size)
      end
    end

    context "when request fails" do
      let(:request_options) { {backoff: 0} }

      context "when succeeds after retries" do
        before do
          expect(adapter).to receive(:call).and_raise(Errno::ECONNRESET).exactly(described_class::MAX_RETRIES).times
          expect(adapter).to receive(:call).and_return(http_response)
        end

        it "produces a response" do
          is_expected.to be_a_kind_of(Datadog::CI::Transport::Adapters::Net::Response)

          expect(response.code).to eq(200)
        end
      end

      context "when retries are exhausted" do
        before do
          expect(adapter).to receive(:call).and_raise(Errno::ECONNRESET).exactly(described_class::MAX_RETRIES + 1).times
        end

        it "returns ErrorRsponse" do
          expect(response.error).to be_kind_of(Errno::ECONNRESET)
        end
      end
    end
  end
end
