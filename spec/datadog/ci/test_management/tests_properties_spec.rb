# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/test_management/tests_properties"

RSpec.describe Datadog::CI::TestManagement::TestsProperties do
  include_context "Telemetry spy"

  let(:api) { spy("api") }

  subject(:client) { described_class.new(api: api) }

  describe "#fetch" do
    subject { client.fetch(test_session) }

    let(:service) { "service" }
    let(:tracer_span) do
      Datadog::Tracing::SpanOperation.new("session", service: service).tap do |span|
        span.set_tags({
          "git.repository_url" => "repository_url",
          "git.commit.message" => "Test commit message",
          "git.commit.sha" => "test_sha"
        })
      end
    end
    let(:test_session) { Datadog::CI::TestSession.new(tracer_span) }

    let(:path) { Datadog::CI::Ext::Transport::DD_API_TEST_MANAGEMENT_TESTS_PATH }

    it "requests the unique tests" do
      subject

      expect(api).to have_received(:api_request) do |args|
        expect(args[:path]).to eq(path)

        data = JSON.parse(args[:payload])["data"]

        expect(data["type"]).to eq(Datadog::CI::Ext::Transport::DD_API_TEST_MANAGEMENT_TESTS_TYPE)

        attributes = data["attributes"]
        expect(attributes["repository_url"]).to eq("repository_url")
        expect(attributes["commit_message"]).to eq("Test commit message")
        expect(attributes["sha"]).to eq("test_sha")
      end
    end

    context "when git commit head info is available" do
      let(:tracer_span) do
        Datadog::Tracing::SpanOperation.new("session", service: service).tap do |span|
          span.set_tags({
            "git.repository_url" => "repository_url",
            "git.commit.message" => "Test commit message",
            "git.commit.sha" => "test_sha",
            "git.commit.head.message" => "Original test commit message",
            "git.commit.head.sha" => "original_test_sha"
          })
        end
      end

      it "requests the unique tests with original commit info" do
        subject

        expect(api).to have_received(:api_request) do |args|
          expect(args[:path]).to eq(path)

          data = JSON.parse(args[:payload])["data"]

          expect(data["type"]).to eq(Datadog::CI::Ext::Transport::DD_API_TEST_MANAGEMENT_TESTS_TYPE)

          attributes = data["attributes"]
          expect(attributes["commit_message"]).to eq("Original test commit message")
          expect(attributes["sha"]).to eq("original_test_sha")
        end
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
                    modules: {
                      "rspec" => {
                        "suites" => {
                          "AdminControllerTest" => {
                            "tests" => {
                              "test_new" => {
                                "properties" => {
                                  "disabled" => false,
                                  "quarantined" => true,
                                  "attempt_to_fix" => true
                                }
                              },
                              "test_index" => {
                                "properties" => {
                                  "disabled" => "true",
                                  "quarantined" => "false"
                                }
                              },
                              "test_create" => {
                                "properties" => {
                                  "disabled" => false,
                                  "quarantined" => true,
                                  "attempt_to_fix" => false
                                }
                              }
                            }
                          },
                          "UsersControllerTest" => {
                            "tests" => {
                              "test_new" => {
                                "properties" => {
                                  "disabled" => false,
                                  "quarantined" => false,
                                  "attempt_to_fix" => false
                                }
                              }
                            }
                          }
                        }
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
            expect(response).to eq({
              "AdminControllerTest.test_new." => {
                "disabled" => false,
                "quarantined" => true,
                "attempt_to_fix" => true

              },
              "AdminControllerTest.test_index." => {
                "disabled" => true,
                "quarantined" => false
              },
              "AdminControllerTest.test_create." => {
                "disabled" => false,
                "quarantined" => true,
                "attempt_to_fix" => false
              },
              "UsersControllerTest.test_new." => {
                "disabled" => false,
                "quarantined" => false,
                "attempt_to_fix" => false
              }
            })
          end

          it_behaves_like "emits telemetry metric", :inc, "test_management_tests.request", 1
          it_behaves_like "emits telemetry metric", :distribution, "test_management_tests.request_ms"
          it_behaves_like "emits telemetry metric", :distribution, "test_management_tests.response_bytes"
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

          it_behaves_like "emits telemetry metric", :inc, "test_management_tests.request_errors", 1
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
            expect(Datadog.logger).to receive(:error).with(/Failed to parse test management tests response payload/)
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
                  "parameters" => "string"
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
  end

  describe Datadog::CI::TestManagement::TestsProperties::Response do
    describe "with json keyword argument" do
      let(:http_response) { double("http_response", ok?: true) }
      let(:json_data) do
        {
          "data" => {
            "attributes" => {
              "modules" => {
                "rspec" => {
                  "suites" => {
                    "TestSuite" => {
                      "tests" => {
                        "test1" => {"properties" => {"disabled" => "false", "quarantined" => "true"}},
                        "test2" => {"properties" => {"disabled" => "true", "quarantined" => "false"}}
                      }
                    }
                  }
                }
              }
            }
          }
        }
      end

      subject(:response) { described_class.from_json(json_data) }

      it "uses provided json instead of parsing http response" do
        expect(response.tests).to eq({
          "TestSuite.test1." => {"disabled" => false, "quarantined" => true},
          "TestSuite.test2." => {"disabled" => true, "quarantined" => false}
        })
      end

      it "does not call JSON.parse on http response payload" do
        expect(JSON).not_to receive(:parse)
        response.tests
      end
    end
  end
end
