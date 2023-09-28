require_relative "../../../../lib/datadog/ci/transport/http"

RSpec.describe Datadog::CI::Transport::HTTP do
  subject(:transport) { described_class.new(host: host, **options) }

  let(:host) { "datadog-host" }
  let(:port) { 8132 }
  let(:timeout) { 10 }
  let(:ssl) { true }
  let(:options) { {} }

  shared_context "HTTP adapter stub" do
    let(:adapter) { instance_double(::Datadog::Core::Transport::HTTP::Adapters::Net) }

    before do
      allow(::Datadog::Core::Transport::HTTP::Adapters::Net).to receive(:new)
        .with(
          transport.host,
          transport.port,
          timeout: transport.timeout,
          ssl: transport.ssl
        ).and_return(http_connection)
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
      let(:env) do
        env = Datadog::Core::Transport::HTTP::Env.new(
          Datadog::Core::Transport::Request.new
        )
        env.body = payload
        env.path = path
        env.headers = headers
        env.verb = "post"
        env
      end
      before do
        expect(adapter).to receive(:call).with(env).and_return(http_response)
      end

      it "produces a response" do
        is_expected.to be_a_kind_of(described_class::ResponseDecorator)

        expect(request.http_response).to be(http_response)
      end
    end

    context "when error in connecting to server" do
      before { expect(adapter).to receive(:request).and_raise(StandardError) }

      it { expect(request).to be_a_kind_of(described_class::InternalErrorResponse) }
    end

    # context "when compressing payload" do
    #   let(:headers) { {"Content-Type" => "application/json"} }
    #   let(:expected_headers) { {"Content-Type" => "application/json", "Content-Encoding" => "gzip"} }
    #   let(:options) { {compress: true} }
    #   let(:post_request) { double(:post_request) }

    #   before do
    #     expect(::Net::HTTP::Post).to receive(:new).with(path, expected_headers).and_return(post_request)
    #     expect(post_request).to receive(:body=).with(Datadog::CI::Transport::Gzip.compress(payload))
    #     expect(http_connection).to receive(:request).with(post_request).and_return(http_response)
    #   end

    #   it { expect(request.http_response).to be(http_response) }
    # end
  end
end
