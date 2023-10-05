require_relative "../../../../lib/datadog/ci/transport/http"

RSpec.describe Datadog::CI::Transport::HTTP do
  subject(:transport) { described_class.new(host: host, **options) }

  let(:host) { "datadog-host" }
  let(:port) { 8132 }
  let(:timeout) { 10 }
  let(:ssl) { true }
  let(:options) { {} }

  shared_context "HTTP connection stub" do
    let(:http_connection) { instance_double(::Net::HTTP) }

    before do
      allow(::Net::HTTP).to receive(:new)
        .with(
          transport.host,
          transport.port
        ).and_return(http_connection)

      allow(http_connection).to receive(:open_timeout=).with(transport.timeout)
      allow(http_connection).to receive(:read_timeout=).with(transport.timeout)
      allow(http_connection).to receive(:use_ssl=).with(transport.ssl)

      allow(http_connection).to receive(:start).and_yield(http_connection)
    end
  end

  describe "#initialize" do
    context "given no options" do
      let(:options) { {} }

      it do
        is_expected.to have_attributes(
          host: host,
          port: nil,
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
    include_context "HTTP connection stub"

    let(:path) { "/api/v1/intake" }
    let(:payload) { '{ "key": "value" }' }
    let(:headers) { {"Content-Type" => "application/json"} }
    let(:request_options) { {} }

    let(:http_response) { double("http_response") }

    subject(:request) { transport.request(path: path, payload: payload, headers: headers, **request_options) }

    context "when request is successful" do
      before { expect(http_connection).to receive(:request).and_return(http_response) }

      it "produces a response" do
        is_expected.to be_a_kind_of(described_class::Response)

        expect(request.http_response).to be(http_response)
      end
    end

    context "when error in connecting to server" do
      before { expect(http_connection).to receive(:request).and_raise(StandardError) }

      it { expect(request).to be_a_kind_of(described_class::InternalErrorResponse) }
    end

    context "when method is unknown" do
      let(:request_options) { {method: "delete"} }

      it { expect { request }.to raise_error("Unknown method delete") }
    end

    context "when compressing payload" do
      let(:headers) { {"Content-Type" => "application/json"} }
      let(:expected_headers) { {"Content-Type" => "application/json", "Content-Encoding" => "gzip"} }
      let(:options) { {compress: true} }
      let(:post_request) { double(:post_request) }

      before do
        expect(::Net::HTTP::Post).to receive(:new).with(path, expected_headers).and_return(post_request)
        expect(post_request).to receive(:body=).with(Datadog::CI::Transport::Gzip.compress(payload))
        expect(http_connection).to receive(:request).with(post_request).and_return(http_response)
      end

      it { expect(request.http_response).to be(http_response) }
    end
  end
end

RSpec.describe Datadog::CI::Transport::HTTP::Response do
  subject(:response) { described_class.new(http_response) }

  let(:http_response) { instance_double(::Net::HTTPResponse) }

  describe "#initialize" do
    it { is_expected.to have_attributes(http_response: http_response) }
  end

  describe "#payload" do
    subject(:payload) { response.payload }

    let(:http_response) { instance_double(::Net::HTTPResponse, body: double("body")) }

    it { is_expected.to be(http_response.body) }
  end

  describe "#code" do
    subject(:code) { response.code }

    let(:http_response) { instance_double(::Net::HTTPResponse, code: "200") }

    it { is_expected.to eq(200) }
  end

  describe "#ok?" do
    subject(:ok?) { response.ok? }

    let(:http_response) { instance_double(::Net::HTTPResponse, code: code) }

    context "when code not 2xx" do
      let(:code) { 199 }

      it { is_expected.to be false }
    end

    context "when code is 200" do
      let(:code) { 200 }

      it { is_expected.to be true }
    end

    context "when code is 299" do
      let(:code) { 299 }

      it { is_expected.to be true }
    end

    context "when code is greater than 299" do
      let(:code) { 300 }

      it { is_expected.to be false }
    end
  end

  describe "#unsupported?" do
    subject(:unsupported?) { response.unsupported? }

    let(:http_response) { instance_double(::Net::HTTPResponse, code: code) }

    context "when code is 400" do
      let(:code) { 400 }

      it { is_expected.to be false }
    end

    context "when code is 415" do
      let(:code) { 415 }

      it { is_expected.to be true }
    end
  end

  describe "#not_found?" do
    subject(:not_found?) { response.not_found? }

    let(:http_response) { instance_double(::Net::HTTPResponse, code: code) }

    context "when code is 400" do
      let(:code) { 400 }

      it { is_expected.to be false }
    end

    context "when code is 404" do
      let(:code) { 404 }

      it { is_expected.to be true }
    end
  end

  describe "#client_error?" do
    subject(:client_error?) { response.client_error? }

    let(:http_response) { instance_double(::Net::HTTPResponse, code: code) }

    context "when code is 399" do
      let(:code) { 399 }

      it { is_expected.to be false }
    end

    context "when code is 400" do
      let(:code) { 400 }

      it { is_expected.to be true }
    end

    context "when code is 499" do
      let(:code) { 499 }

      it { is_expected.to be true }
    end

    context "when code is 500" do
      let(:code) { 500 }

      it { is_expected.to be false }
    end
  end

  describe "#server_error?" do
    subject(:server_error?) { response.server_error? }

    let(:http_response) { instance_double(::Net::HTTPResponse, code: code) }

    context "when code is 499" do
      let(:code) { 499 }

      it { is_expected.to be false }
    end

    context "when code is 500" do
      let(:code) { 500 }

      it { is_expected.to be true }
    end

    context "when code is 599" do
      let(:code) { 599 }

      it { is_expected.to be true }
    end

    context "when code is 600" do
      let(:code) { 600 }

      it { is_expected.to be false }
    end
  end

  describe "#internal_error?" do
    subject(:internal_error?) { response.internal_error? }

    it { is_expected.to be false }
  end
end

RSpec.describe Datadog::CI::Transport::HTTP::InternalErrorResponse do
  subject(:response) { described_class.new(error) }

  let(:error) { instance_double(StandardError, class: "StandardError", to_s: "error message") }

  describe "#initialize" do
    it { is_expected.to have_attributes(error: error) }
  end

  describe "#payload" do
    subject(:payload) { response.payload }

    it { is_expected.to eq("") }
  end

  describe "#code" do
    subject(:code) { response.code }

    it { is_expected.to eq(-1) }
  end

  describe "#ok?" do
    subject(:ok?) { response.ok? }

    it { is_expected.to be false }
  end

  describe "#unsupported?" do
    subject(:unsupported?) { response.unsupported? }

    it { is_expected.to be false }
  end

  describe "#not_found?" do
    subject(:not_found?) { response.not_found? }

    it { is_expected.to be false }
  end

  describe "#client_error?" do
    subject(:client_error?) { response.client_error? }

    it { is_expected.to be false }
  end

  describe "#server_error?" do
    subject(:server_error?) { response.server_error? }

    it { is_expected.to be false }
  end

  describe "#internal_error?" do
    subject(:internal_error?) { response.internal_error? }

    it { is_expected.to be true }
  end

  describe "#inspect" do
    subject(:inspect) { response.inspect }

    it { is_expected.to include("error_class:StandardError, error:error message") }
  end
end
