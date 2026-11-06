require "webmock"
require "socket"
require "tmpdir"
require "fileutils"

require_relative "../../../../../lib/datadog/ci/transport/adapters/net"

RSpec.describe Datadog::CI::Transport::Adapters::Net do
  subject(:adapter) do
    described_class.new(hostname: hostname, port: port, ssl: ssl, timeout_seconds: timeout)
  end

  let(:hostname) { "hostname" }
  let(:port) { 9999 }
  let(:timeout) { 15 }
  let(:ssl) { false }

  shared_context "HTTP connection stub" do
    let(:http_connection) { instance_double(::Net::HTTP) }

    before do
      allow(::Net::HTTP).to receive(:new)
        .with(
          adapter.hostname,
          adapter.port
        ).and_return(http_connection)

      allow(http_connection).to receive(:open_timeout=).with(adapter.timeout)
      allow(http_connection).to receive(:read_timeout=).with(adapter.timeout)
      allow(http_connection).to receive(:use_ssl=).with(adapter.ssl)

      allow(http_connection).to receive(:start).and_yield(http_connection)
    end
  end

  describe "#initialize" do
    context "given a :timeout option" do
      let(:timeout) { double("timeout") }

      it { is_expected.to have_attributes(timeout: timeout) }
    end

    context "given a :ssl option" do
      context "with true" do
        let(:ssl) { true }

        it { is_expected.to have_attributes(ssl: true) }
      end
    end
  end

  describe "#open" do
    include_context "HTTP connection stub"

    it "opens and yields a Net::HTTP connection" do
      expect { |b| adapter.open(&b) }.to yield_with_args(http_connection)
    end
  end

  describe "#call" do
    let(:path) { "/foo" }
    let(:body) { "{}" }
    let(:headers) { {} }
    let(:expected_headers) { {"DD-Internal-Untraced-Request" => "1"} }

    subject(:call) { adapter.call(verb: verb, path: path, payload: body, headers: headers) }

    context "with mocked HTTP and verb" do
      context ":post" do
        include_context "HTTP connection stub"

        let(:verb) { :post }
        let(:http_response) { double("http_response") }
        let(:post) { instance_double(Net::HTTP::Post) }

        it "makes a POST and produces a response" do
          expect(Net::HTTP::Post)
            .to receive(:new)
            .with(path, expected_headers)
            .and_return(post)

          expect(post)
            .to receive(:body=)
            .with(body)

          expect(http_connection)
            .to receive(:request)
            .with(post)
            .and_return(http_response)

          is_expected.to be_a_kind_of(described_class::Response)
          expect(call.http_response).to be(http_response)
        end
      end

      context ":get" do
        let(:verb) { :get }

        it { expect { call }.to raise_error("Unknown HTTP method [get]") }
      end
    end

    context "with webmock" do
      let(:hostname) { "127.0.0.1" }
      let(:timeout) { 0.5 }
      let(:verb) { :post }
      let(:expected_error) do
        Errno::ECONNREFUSED
      end

      before { WebMock.enable! }
      after { WebMock.disable! }

      it "makes a request and fails" do
        expect { call }.to raise_error(expected_error)
      end
    end
  end

  context "with a uds_path" do
    subject(:adapter) do
      described_class.new(hostname: nil, port: nil, ssl: false, timeout_seconds: 5, uds_path: uds_path)
    end

    let(:socket_dir) { Dir.mktmpdir("datadog-ci-") }
    let(:uds_path) { File.join(socket_dir, "apm.socket") }
    let(:server) { UNIXServer.new(uds_path) }
    let(:received) { Queue.new }
    let!(:server_thread) do
      listening = server
      Thread.new do
        connection = listening.accept
        request_line = connection.gets
        headers = {}
        while (line = connection.gets) && line != "\r\n"
          name, value = line.split(":", 2)
          headers[name.downcase] = value.strip
        end
        body = connection.read(headers["content-length"].to_i)
        received << [request_line, headers, body]
        connection.write("HTTP/1.1 202 Accepted\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}")
        connection.close
      end
    end

    before do
      WebMock.enable!
      WebMock.disable_net_connect!
    end

    after do
      WebMock.allow_net_connect!
      WebMock.disable!
      server_thread.join(5)
      server.close
      FileUtils.remove_entry(socket_dir)
    end

    it "sends the request over the socket, out of WebMock's reach" do
      response = adapter.call(verb: "post", path: "/evp_proxy/v4/api/v2/citestcycle", payload: "{}", headers: {})

      expect(response.code).to eq(202)
      expect(response.payload).to eq("{}")
      request_line, headers, body = received.pop
      expect(request_line).to eq("POST /evp_proxy/v4/api/v2/citestcycle HTTP/1.1\r\n")
      expect(headers["host"]).to eq("localhost")
      expect(body).to eq("{}")
    end
  end

  describe "#post" do
    include_context "HTTP connection stub"

    let(:path) { "/foo" }
    let(:body) { "{}" }
    let(:headers) { {} }

    subject(:post) { adapter.post(path: path, payload: body, headers: headers) }

    let(:http_response) { double("http_response") }

    before { expect(http_connection).to receive(:request).and_return(http_response) }

    it "produces a response" do
      is_expected.to be_a_kind_of(described_class::Response)
      expect(post.http_response).to be(http_response)
    end
  end
end

RSpec.describe Datadog::CI::Transport::Adapters::Net::Response do
  subject(:response) { described_class.new(http_response) }

  let(:http_response) { instance_double(::Net::HTTPResponse) }

  describe "#initialize" do
    it { is_expected.to have_attributes(http_response: http_response) }
  end

  describe "#payload" do
    subject(:payload) { response.payload }
    let(:encoding) { "plain/text" }

    let(:http_response) { instance_double(::Net::HTTPResponse, body: "body") }

    before do
      expect(http_response).to receive(:[]).with("Content-Encoding").and_return(encoding)
    end

    it { is_expected.to be(http_response.body) }

    context "when payload is gzipped" do
      let(:expected_payload) { "sample_payload" }
      let(:encoding) { "gzip" }
      let(:http_response) do
        instance_double(::Net::HTTPResponse, body: Datadog::CI::Transport::Gzip.compress(expected_payload))
      end

      it { is_expected.to eq(expected_payload) }
    end
  end

  describe "#code" do
    subject(:code) { response.code }

    let(:http_response) { instance_double(::Net::HTTPResponse, code: "200") }

    it { is_expected.to eq(200) }
  end

  describe "#ok?" do
    subject(:ok?) { response.ok? }

    let(:http_response) { instance_double(::Net::HTTPResponse, code: code) }

    context "when code is 199" do
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

    context "when code is 300" do
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

  describe "#header" do
    subject(:header) { response.header(name) }

    let(:name) { "name" }
    let(:value) { "value" }
    let(:http_response) { instance_double(::Net::HTTPResponse) }

    before do
      expect(http_response).to receive(:[]).with(name).and_return(value)
    end

    it { is_expected.to eq(value) }
  end
end
