# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/test_impact_analysis/skippable"

RSpec.describe Datadog::CI::TestImpactAnalysis::Skippable do
  include_context "Telemetry spy"

  let(:api) { spy("api") }
  let(:dd_env) { "ci" }
  let(:config_tags) { {} }

  subject(:client) { described_class.new(api: api, dd_env: dd_env, config_tags: config_tags) }

  describe "#fetch_skippable_tests" do
    subject { client.fetch_skippable_tests(test_session) }

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

    let(:path) { Datadog::CI::Ext::Transport::DD_API_SKIPPABLE_TESTS_PATH }

    it "requests the skippable tests" do
      subject

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
        expect(configurations["os.version"]).to eq("version")
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
              }.to_json,
              request_compressed: false,
              duration_ms: 1.2,
              gzipped_content?: false,
              response_size: 100
            )
          end

          it "parses the response" do
            expect(response.ok?).to be true
            expect(response.correlation_id).to eq("correlation_id_123")
            expect(response.tests).to eq(Set.new(["test_suite_name.test_name.string"]))
            expect(response.error_message).to be_nil
          end

          it_behaves_like "emits telemetry metric", :inc, "itr_skippable_tests.request", 1
          it_behaves_like "emits telemetry metric", :distribution, "itr_skippable_tests.request_ms"
          it_behaves_like "emits telemetry metric", :distribution, "itr_skippable_tests.response_bytes"
        end

        context "when response is not OK" do
          let(:http_response) do
            double(
              "http_response",
              ok?: false,
              payload: "not authorized",
              request_compressed: false,
              duration_ms: 1.2,
              gzipped_content?: false,
              response_size: 100,
              telemetry_error_type: nil,
              code: 422
            )
          end

          it "parses the response" do
            expect(response.ok?).to be false
            expect(response.correlation_id).to be_nil
            expect(response.tests).to be_empty
            expect(response.error_message).to eq("Status code: 422, response: not authorized")
          end

          it_behaves_like "emits telemetry metric", :inc, "itr_skippable_tests.request_errors", 1
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
              }.to_json,
              request_compressed: false,
              duration_ms: 1.2,
              gzipped_content?: false,
              response_size: 100
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

    context "when there are custom configurations" do
      let(:config_tags) do
        {
          "tag1" => "value1"
        }
      end

      it "requests the skippable tests with custom configurations" do
        subject

        expect(api).to have_received(:api_request) do |args|
          data = JSON.parse(args[:payload])["data"]
          configurations = data["attributes"]["configurations"]

          expect(configurations["custom"]).to eq("tag1" => "value1")
        end
      end
    end
  end

  describe Datadog::CI::TestImpactAnalysis::Skippable::Response do
    describe "with json keyword argument" do
      let(:http_response) { double("http_response", ok?: true) }
      let(:json_data) do
        {
          "meta" => {"correlation_id" => "test_correlation_123"},
          "data" => [
            {
              "type" => "test",
              "attributes" => {"suite" => "TestSuite", "name" => "test1", "parameters" => "params1"}
            },
            {
              "type" => "test",
              "attributes" => {"suite" => "TestSuite", "name" => "test2", "parameters" => nil}
            }
          ]
        }
      end

      subject(:response) { described_class.from_json(json_data) }

      it "uses provided json instead of parsing http response" do
        expect(response.correlation_id).to eq("test_correlation_123")
        expect(response.tests).to eq(Set.new(["TestSuite.test1.params1", "TestSuite.test2."]))
      end

      it "does not call JSON.parse on http response payload" do
        expect(JSON).not_to receive(:parse)
        response.tests
      end
    end
  end
end
