# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/itr/skippable"

RSpec.describe Datadog::CI::ITR::Skippable do
  let(:api) { spy("api") }
  let(:dd_env) { "ci" }

  subject(:client) { described_class.new(api: api, dd_env: dd_env) }

  describe "#fetch_skippable_tests" do
    let(:service) { "service" }
    let(:tracer_span) do
      Datadog::Tracing::SpanOperation.new("session", service: service).tap do |span|
        span.set_tags({
          "git.repository_url" => "repository_url",
          "git.branch" => "branch",
          "git.commit.sha" => "commit_sha",
          "os.platform" => "platform",
          "os.architecture" => "arch",
          "runtime.name" => "runtime_name",
          "runtime.version" => "runtime_version"
        })
      end
    end
    let(:test_session) { Datadog::CI::TestSession.new(tracer_span) }

    let(:path) { Datadog::CI::Ext::Transport::DD_API_SKIPPABLE_TESTS_PATH }

    it "requests the skippable tests" do
      client.fetch_skippable_tests(test_session)

      expect(api).to have_received(:api_request) do |args|
        expect(args[:path]).to eq(path)

        data = JSON.parse(args[:payload])["data"]

        expect(data["type"]).to eq(Datadog::CI::Ext::Transport::DD_API_SKIPPABLE_TESTS_TYPE)

        attributes = data["attributes"]
        expect(attributes["service"]).to eq(service)
        expect(attributes["env"]).to eq(dd_env)
        expect(attributes["test_level"]).to eq("test")
        expect(attributes["repository_url"]).to eq("repository_url")
        expect(attributes["sha"]).to eq("commit_sha")

        configurations = attributes["configurations"]
        expect(configurations["os.platform"]).to eq("platform")
        expect(configurations["os.architecture"]).to eq("arch")
        expect(configurations["runtime.name"]).to eq("runtime_name")
        expect(configurations["runtime.version"]).to eq("runtime_version")
      end
    end

    context "parsing response" do
      subject(:response) { client.fetch_skippable_tests(test_session) }

      context "when api is present" do
        before do
          allow(api).to receive(:api_request).and_return(http_response)
        end

        context "when response is OK" do
          let(:http_response) do
            double(
              "http_response",
              ok?: true,
              payload: {
                "meta" => {
                  "correlation_id" => "correlation_id_123"
                },
                "data" => [
                  {
                    "id" => "123",
                    "type" => Datadog::CI::Ext::Test::ITR_TEST_SKIPPING_MODE,
                    "attributes" => {
                      "suite" => "test_suite_name",
                      "name" => "test_name",
                      "parameters" => "string",
                      "configurations" => {
                        "os.platform" => "linux",
                        "os.version" => "bionic",
                        "os.architecture" => "amd64",
                        "runtime.vendor" => "string",
                        "runtime.architecture" => "amd64"
                      }
                    }
                  }
                ]
              }.to_json
            )
          end

          it "parses the response" do
            expect(response.ok?).to be true
            expect(response.correlation_id).to eq("correlation_id_123")
            expect(response.tests.first).to eq(
              Datadog::CI::ITR::Skippable::Test.new(name: "test_name", suite: "test_suite_name")
            )
          end
        end

        context "when response is not OK" do
          let(:http_response) do
            double(
              "http_response",
              ok?: false,
              payload: ""
            )
          end

          it "parses the response" do
            expect(response.ok?).to be false
            expect(response.correlation_id).to be_nil
            expect(response.tests).to be_empty
          end
        end

        context "when response is OK but JSON is malformed" do
          let(:http_response) do
            double(
              "http_response",
              ok?: true,
              payload: "not json"
            )
          end

          before do
            expect(Datadog.logger).to receive(:error).with(/Failed to parse skippable tests response payload/)
          end

          it "parses the response" do
            expect(response.ok?).to be true
            expect(response.correlation_id).to be_nil
            expect(response.tests).to be_empty
          end
        end

        context "when response is OK but JSON has different format" do
          let(:http_response) do
            double(
              "http_response",
              ok?: true,
              payload: {
                "attributes" => {
                  "suite" => "test_suite_name",
                  "name" => "test_name",
                  "parameters" => "string",
                  "configurations" => {
                    "os.platform" => "linux",
                    "os.version" => "bionic",
                    "os.architecture" => "amd64",
                    "runtime.vendor" => "string",
                    "runtime.architecture" => "amd64"
                  }
                }
              }.to_json
            )
          end

          it "parses the response" do
            expect(response.ok?).to be true
            expect(response.correlation_id).to be_nil
            expect(response.tests).to be_empty
          end
        end
      end

      context "when there is no api" do
        let(:api) { nil }

        it "returns an empty response" do
          expect(response.ok?).to be false
          expect(response.correlation_id).to be_nil
          expect(response.tests).to be_empty
        end
      end
    end
  end
end
