# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/remote/library_settings_client"

RSpec.describe Datadog::CI::Remote::LibrarySettingsClient do
  include_context "Telemetry spy"

  let(:dd_env) { "ci" }
  let(:config_tags) { {} }

  subject(:client) { described_class.new(api: api, dd_env: dd_env, config_tags: config_tags) }

  describe "#fetch" do
    subject(:response) { client.fetch(test_session) }

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

    context "when api is present" do
      let(:api) { spy("api") }
      before do
        allow(api).to receive(:api_request).and_return(http_response)
      end

      let(:attributes) do
        {
          "code_coverage" => "1",
          "tests_skipping" => "false",
          "itr_enabled" => "True",
          "require_git" => require_git,
          "flaky_test_retries_enabled" => "true",
          "known_tests_enabled" => "true",
          "impacted_tests_enabled" => "true",
          "coverage_report_upload_enabled" => "true",
          "early_flake_detection" => {
            "enabled" => "true",
            "slow_test_retries" => {
              "5s" => 10,
              "10s" => 5,
              "30s" => 3,
              "5m" => 2
            },
            "faulty_session_threshold" => 30
          },
          "test_management" => {
            "enabled" => "0",
            "attempt_to_fix_retries" => 40
          }
        }
      end

      let(:http_response) do
        double(
          "http_response",
          ok?: true,
          payload: {
            "data" => {
              "id" => "123",
              "type" => Datadog::CI::Ext::Transport::DD_API_SETTINGS_TYPE,
              "attributes" => attributes
            }
          }.to_json,
          request_compressed: false,
          duration_ms: 1.2
        )
      end

      let(:require_git) { false }

      let(:path) { Datadog::CI::Ext::Transport::DD_API_SETTINGS_PATH }

      it "requests the settings" do
        subject

        expect(api).to have_received(:api_request) do |args|
          expect(args[:path]).to eq(path)

          data = JSON.parse(args[:payload])["data"]

          expect(data["id"]).to eq(Datadog::Core::Environment::Identity.id)
          expect(data["type"]).to eq(Datadog::CI::Ext::Transport::DD_API_SETTINGS_TYPE)

          attributes = data["attributes"]
          expect(attributes["service"]).to eq(service)
          expect(attributes["env"]).to eq(dd_env)
          expect(attributes["test_level"]).to eq("test")
          expect(attributes["repository_url"]).to eq("repository_url")
          expect(attributes["branch"]).to eq("branch")
          expect(attributes["sha"]).to eq("commit_sha")

          configurations = attributes["configurations"]
          expect(configurations["os.platform"]).to eq("platform")
          expect(configurations["os.architecture"]).to eq("arch")
          expect(configurations["os.version"]).to eq("version")
          expect(configurations["runtime.name"]).to eq("runtime_name")
          expect(configurations["runtime.version"]).to eq("runtime_version")
        end
      end

      context "when git.branch is not present but git.tag is" do
        let(:tracer_span) do
          Datadog::Tracing::SpanOperation.new("session", service: service).tap do |span|
            span.set_tags({
              "git.repository_url" => "repository_url",
              "git.tag" => "tag",
              "git.commit.sha" => "commit_sha",
              "os.platform" => "platform",
              "os.architecture" => "arch",
              "os.version" => "version",
              "runtime.name" => "runtime_name",
              "runtime.version" => "runtime_version"
            })
          end
        end

        it "requests the settings with the tag" do
          subject

          expect(api).to have_received(:api_request) do |args|
            attributes = JSON.parse(args[:payload])["data"]["attributes"]
            expect(attributes["branch"]).to eq("tag")
          end
        end
      end

      context "parsing response" do
        context "when response is OK" do
          it "parses the response" do
            expect(response.ok?).to be true
            expect(response.payload).to eq(attributes)
            expect(response.require_git?).to be false
            expect(response.itr_enabled?).to be true
            expect(response.code_coverage_enabled?).to be true
            expect(response.tests_skipping_enabled?).to be false
            expect(response.flaky_test_retries_enabled?).to be true
            expect(response.early_flake_detection_enabled?).to be true
            expect(response.known_tests_enabled?).to be true
            expect(response.impacted_tests_enabled?).to be true
            expect(response.coverage_report_upload_enabled?).to be true
            expect(response.slow_test_retries.entries).to eq(
              [
                Datadog::CI::Remote::SlowTestRetries::Entry.new(5.0, 10),
                Datadog::CI::Remote::SlowTestRetries::Entry.new(10.0, 5),
                Datadog::CI::Remote::SlowTestRetries::Entry.new(30.0, 3),
                Datadog::CI::Remote::SlowTestRetries::Entry.new(300.0, 2)
              ]
            )
            expect(response.faulty_session_threshold).to eq(30)
            expect(response.test_management_enabled?).to be(false)
            expect(response.attempt_to_fix_retries_count).to eq(40)

            metric = telemetry_metric(:inc, "git_requests.settings_response")
            expect(metric.tags).to eq(
              "coverage_enabled" => "true",
              "itr_enabled" => "true",
              "itrskip_enabled" => "false",
              "early_flake_detection_enabled" => "true",
              "flaky_test_retries_enabled" => "true",
              "known_tests_enabled" => "true",
              "require_git" => "false"
            )
          end

          it_behaves_like "emits telemetry metric", :inc, "git_requests.settings", 1
          it_behaves_like "emits telemetry metric", :distribution, "git_requests.settings_ms"
          it_behaves_like "emits telemetry metric", :inc, "git_requests.settings_response"

          context "when git is required" do
            let(:require_git) { "True" }

            it "parses the response" do
              expect(response.require_git?).to be true
            end
          end

          context "with custom configuration" do
            let(:config_tags) { {"key" => "value"} }

            it "requests the settings" do
              subject

              expect(api).to have_received(:api_request) do |args|
                data = JSON.parse(args[:payload])["data"]

                attributes = data["attributes"]
                configurations = attributes["configurations"]
                expect(configurations["custom"]).to eq("key" => "value")
              end
            end
          end
        end

        context "when response is not OK" do
          let(:http_response) do
            double(
              "http_response",
              ok?: false,
              payload: "",
              request_compressed: false,
              duration_ms: 1.2,
              telemetry_error_type: "network",
              code: nil
            )
          end

          it "parses the response" do
            expect(response.ok?).to be false
            expect(response.payload).to eq("itr_enabled" => false)
            expect(response.require_git?).to be false
          end

          it_behaves_like "emits telemetry metric", :inc, "git_requests.settings_errors", 1
        end

        context "when response is OK but JSON is malformed" do
          let(:http_response) do
            double(
              "http_response",
              ok?: true,
              payload: "not json",
              request_compressed: false,
              duration_ms: 1.2
            )
          end

          before do
            expect(Datadog.logger).to receive(:error).with(/Failed to parse settings response payload/)
          end

          it "returns default response" do
            expect(response.ok?).to be true
            expect(response.payload).to eq("itr_enabled" => false)
            expect(response.require_git?).to be false

            metric = telemetry_metric(:inc, "git_requests.settings_errors")
            expect(metric.value).to eq(1)
            expect(metric.tags).to eq("error_type" => "invalid_json")
          end
        end

        context "when response is OK but JSON has different format" do
          let(:http_response) do
            double(
              "http_response",
              ok?: true,
              payload: {
                "attributes" => {
                  "code_coverage" => true,
                  "tests_skipping" => false,
                  "itr_enabled" => true,
                  "require_git" => false
                }
              }.to_json,
              request_compressed: false,
              duration_ms: 1.2
            )
          end

          it "parses the response" do
            expect(response.ok?).to be true
            expect(response.payload).to eq("itr_enabled" => false)
            expect(response.require_git?).to be false
          end
        end
      end
    end

    context "when there is no api" do
      let(:api) { nil }

      it "returns an empty response" do
        expect(response.ok?).to be false
        expect(response.payload).to eq("itr_enabled" => false)
        expect(response.require_git?).to be false
      end
    end
  end

  describe Datadog::CI::Remote::LibrarySettings do
    describe "with json keyword argument" do
      let(:http_response) { double("http_response", ok?: false) }
      let(:json_data) { {"itr_enabled" => "true", "code_coverage" => "1", "tests_skipping" => "false"} }

      subject(:settings) { described_class.from_json(json_data) }

      it "uses provided json instead of parsing http response" do
        expect(settings.payload).to eq(json_data)
        expect(settings.itr_enabled?).to be true
        expect(settings.code_coverage_enabled?).to be true
        expect(settings.tests_skipping_enabled?).to be false
      end

      it "does not call JSON.parse on http response payload" do
        expect(JSON).not_to receive(:parse)
        settings.payload
      end
    end
  end
end
