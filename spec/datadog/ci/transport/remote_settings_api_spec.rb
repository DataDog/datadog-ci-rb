# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/transport/remote_settings_api"

RSpec.describe Datadog::CI::Transport::RemoteSettingsApi do
  let(:api) { spy("api") }
  let(:dd_env) { "ci" }

  subject(:client) { described_class.new(api: api, dd_env: dd_env) }

  describe "#fetch_library_settings" do
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

    let(:path) { Datadog::CI::Ext::Transport::DD_API_SETTINGS_PATH }

    it "requests the settings" do
      client.fetch_library_settings(test_session)

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

    context "parsing response" do
      subject(:response) { client.fetch_library_settings(test_session) }

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
                "data" => {
                  "id" => "123",
                  "type" => Datadog::CI::Ext::Transport::DD_API_SETTINGS_TYPE,
                  "attributes" => {
                    "code_coverage" => true,
                    "tests_skipping" => false,
                    "itr_enabled" => true,
                    "require_git" => require_git
                  }
                }
              }.to_json
            )
          end
          let(:require_git) { false }

          it "parses the response" do
            expect(response.ok?).to be true
            expect(response.payload).to eq({
              "code_coverage" => true,
              "tests_skipping" => false,
              "itr_enabled" => true,
              "require_git" => require_git
            })
            expect(response.require_git?).to be false
          end

          context "when git is required" do
            let(:require_git) { "True" }

            it "parses the response" do
              expect(response.require_git?).to be true
            end
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
            expect(response.payload).to eq("itr_enabled" => false)
            expect(response.require_git?).to be false
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
            expect(Datadog.logger).to receive(:error).with(/Failed to parse settings response payload/)
          end

          it "parses the response" do
            expect(response.ok?).to be true
            expect(response.payload).to eq("itr_enabled" => false)
            expect(response.require_git?).to be false
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
              }.to_json
            )
          end

          it "parses the response" do
            expect(response.ok?).to be true
            expect(response.payload).to eq("itr_enabled" => false)
            expect(response.require_git?).to be false
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
  end
end
