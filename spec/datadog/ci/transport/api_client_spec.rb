require_relative "../../../../lib/datadog/ci/transport/api_client"

RSpec.describe Datadog::CI::Transport::ApiClient do
  let(:api) { spy("api") }
  let(:dd_env) { "ci" }

  subject { described_class.new(api: api, dd_env: dd_env) }

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
          "runtime.name" => "runtime_name",
          "runtime.version" => "runtime_version"
        })
      end
    end
    let(:test_session) { Datadog::CI::TestSession.new(tracer_span) }

    let(:path) { Datadog::CI::Ext::Transport::DD_API_SETTINGS_PATH }

    it "requests the settings" do
      subject.fetch_library_settings(test_session)

      expect(api).to have_received(:api_request) do |args|
        expect(args[:path]).to eq(path)

        data = JSON.parse(args[:payload])["data"]

        expect(data["id"]).to eq(Datadog::Core::Environment::Identity.id)
        expect(data["type"]).to eq(Datadog::CI::Ext::Transport::DD_API_SETTINGS_TYPE)

        attributes = data["attributes"]
        expect(attributes["service"]).to eq(service)
        expect(attributes["env"]).to eq(dd_env)
        expect(attributes["repository_url"]).to eq("repository_url")
        expect(attributes["branch"]).to eq("branch")
        expect(attributes["sha"]).to eq("commit_sha")

        configurations = attributes["configurations"]
        expect(configurations["os.platform"]).to eq("platform")
        expect(configurations["os.arch"]).to eq("arch")
        expect(configurations["runtime.name"]).to eq("runtime_name")
        expect(configurations["runtime.version"]).to eq("runtime_version")
      end
    end
  end
end
