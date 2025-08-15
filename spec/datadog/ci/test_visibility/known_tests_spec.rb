# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/test_visibility/known_tests"

RSpec.describe Datadog::CI::TestVisibility::KnownTests do
  include_context "Telemetry spy"

  let(:api) { spy("api") }
  let(:dd_env) { "ci" }
  let(:config_tags) { {} }

  subject(:client) { described_class.new(api: api, dd_env: dd_env, config_tags: config_tags) }

  describe "#fetch" do
    subject { client.fetch(test_session) }

    let(:service) { "service" }
    let(:tracer_span) do
      Datadog::Tracing::SpanOperation.new("session", service: service).tap do |span|
        span.set_tags({
          "git.repository_url" => "repository_url",
          "git.branch" => "branch",
          "git.commit.sha" => "commit_sha",
          "os.platform" => "platform",
          "os.architecture" => "arch",
          "os.version" => "version",
          "runtime.name" => "runtime_name",
          "runtime.version" => "runtime_version"
        })
      end
    end
    let(:test_session) { Datadog::CI::TestSession.new(tracer_span) }

    let(:path) { Datadog::CI::Ext::Transport::DD_API_UNIQUE_TESTS_PATH }

    it "requests the unique tests" do
      subject

      expect(api).to have_received(:api_request) do |args|
        expect(args[:path]).to eq(path)

        data = JSON.parse(args[:payload])["data"]

        expect(data["type"]).to eq(Datadog::CI::Ext::Transport::DD_API_UNIQUE_TESTS_TYPE)

        attributes = data["attributes"]
        expect(attributes["service"]).to eq(service)
        expect(attributes["env"]).to eq(dd_env)
        expect(attributes["repository_url"]).to eq("repository_url")
        expect(attributes["sha"]).to eq("commit_sha")

        configurations = attributes["configurations"]
        expect(configurations["os.platform"]).to eq("platform")
        expect(configurations["os.architecture"]).to eq("arch")
        expect(configurations["os.version"]).to eq("version")
        expect(configurations["runtime.name"]).to eq("runtime_name")
        expect(configurations["runtime.version"]).to eq("runtime_version")
      end
    end

    context "parsing response" do
      subject(:response) { client.fetch(test_session) }

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
                data: {
                  id: "wTGavjGXpUg",
                  type: "ci_app_libraries_tests",
                  attributes: {
                    tests: {
                      "rspec" => {
                        "AdminControllerTest" => [
                          "test_new",
                          "test_index",
                          "test_create"
                        ]
                      }
                    }
                  }
                }
              }.to_json,
              request_compressed: false,
              duration_ms: 1.2,
              gzipped_content?: false,
              response_size: 100
            )
          end

          it "parses the response" do
            expect(response).to eq(Set.new(["AdminControllerTest.test_new.", "AdminControllerTest.test_index.", "AdminControllerTest.test_create."]))
          end

          it_behaves_like "emits telemetry metric", :inc, "known_tests.request", 1
          it_behaves_like "emits telemetry metric", :distribution, "known_tests.request_ms"
          it_behaves_like "emits telemetry metric", :distribution, "known_tests.response_bytes"
        end

        context "when response is not OK" do
          let(:http_response) do
            double(
              "http_response",
              ok?: false,
              payload: "",
              request_compressed: false,
              duration_ms: 1.2,
              gzipped_content?: false,
              response_size: 100,
              telemetry_error_type: nil,
              code: 422
            )
          end

          it "parses the response" do
            expect(response).to be_empty
          end

          it_behaves_like "emits telemetry metric", :inc, "known_tests.request_errors", 1
        end

        context "when response is OK but JSON is malformed" do
          let(:http_response) do
            double(
              "http_response",
              ok?: true,
              payload: "not json",
              request_compressed: false,
              duration_ms: 1.2,
              gzipped_content?: false,
              response_size: 100
            )
          end

          before do
            expect(Datadog.logger).to receive(:error).with(/Failed to parse unique known tests response payload/)
          end

          it "parses the response" do
            expect(response).to be_empty
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
              }.to_json,
              request_compressed: false,
              duration_ms: 1.2,
              gzipped_content?: false,
              response_size: 100
            )
          end

          it "parses the response" do
            expect(response).to be_empty
          end
        end
      end

      context "when there is no api" do
        let(:api) { nil }

        it "returns an empty response" do
          expect(response).to be_empty
        end
      end
    end

    context "when there are custom configurations" do
      let(:config_tags) do
        {
          "tag1" => "value1"
        }
      end

      it "requests the unique tests with custom configurations" do
        subject

        expect(api).to have_received(:api_request) do |args|
          data = JSON.parse(args[:payload])["data"]
          configurations = data["attributes"]["configurations"]

          expect(configurations["custom"]).to eq("tag1" => "value1")
        end
      end
    end
  end

  describe Datadog::CI::TestVisibility::KnownTests::Response do
    describe "with json keyword argument" do
      let(:http_response) { double("http_response", ok?: true) }
      let(:json_data) { {"data" => {"attributes" => {"tests" => {"rspec" => {"TestSuite" => ["test1", "test2"]}}}}} }

      subject(:response) { described_class.new(http_response, json: json_data) }

      it "uses provided json instead of parsing http response" do
        expect(response.tests).to eq(Set.new(["TestSuite.test1.", "TestSuite.test2."]))
      end

      it "does not call JSON.parse on http response payload" do
        expect(JSON).not_to receive(:parse)
        response.tests
      end
    end
  end
end
