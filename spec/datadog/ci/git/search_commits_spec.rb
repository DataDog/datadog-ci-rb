# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/git/search_commits"

RSpec.describe Datadog::CI::Git::SearchCommits do
  let(:api) { double("api") }
  subject(:search_commits) { described_class.new(api: api) }

  describe "#call" do
    let(:repository_url) { "https://datadoghq.com/git/test.git" }
    let(:commits) { ["c7f893648f656339f62fb7b4d8a6ecdf7d063835"] }

    context "when the API is not configured" do
      let(:api) { nil }

      it "raises an error" do
        expect { search_commits.call(repository_url, commits) }
          .to raise_error(Datadog::CI::Git::SearchCommits::ApiError, "test visibility API is not configured")
      end
    end

    context "when the API is configured" do
      before do
        allow(api).to receive(:api_request).and_return(http_response)
      end

      context "when the API request fails" do
        let(:http_response) { double("http_response", ok?: false, body: "error message") }

        it "raises an error" do
          expect { search_commits.call(repository_url, commits) }
            .to raise_error(Datadog::CI::Git::SearchCommits::ApiError, "Failed to search commits: error message")
        end
      end

      context "when the API request is successful" do
        let(:http_response) { double("http_response", ok?: true, payload: response_payload) }
        let(:response_payload) do
          {
            "data" => [
              {
                "id" => "c7f893648f656339f62fb7b4d8a6ecdf7d063835",
                "type" => "commit"
              }
            ]
          }.to_json
        end

        it "returns the list of commit SHAs" do
          expect(api).to receive(:api_request).with(
            path: Datadog::CI::Ext::Transport::DD_API_GIT_SEARCH_COMMITS_PATH,
            payload: "{\"meta\":{\"repository_url\":\"https://datadoghq.com/git/test.git\"},\"data\":[{\"id\":\"c7f893648f656339f62fb7b4d8a6ecdf7d063835\",\"type\":\"commit\"}]}"
          ).and_return(http_response)

          expect(search_commits.call(repository_url, commits)).to eq(Set.new(["c7f893648f656339f62fb7b4d8a6ecdf7d063835"]))
        end

        context "when the request contains an invalid commit SHA" do
          let(:commits) { ["INVALID_SHA", "c7f893648f656339f62fb7b4d8a6ecdf7d063835"] }

          it "does not include the invalid commit SHA in the request" do
            expect(api).to receive(:api_request).with(
              path: Datadog::CI::Ext::Transport::DD_API_GIT_SEARCH_COMMITS_PATH,
              payload: "{\"meta\":{\"repository_url\":\"https://datadoghq.com/git/test.git\"},\"data\":[{\"id\":\"c7f893648f656339f62fb7b4d8a6ecdf7d063835\",\"type\":\"commit\"}]}"
            ).and_return(http_response)

            expect(search_commits.call(repository_url, commits)).to eq(Set.new(["c7f893648f656339f62fb7b4d8a6ecdf7d063835"]))
          end
        end

        context "when the response contains an invalid commit type" do
          let(:response_payload) do
            {
              "data" => [
                {
                  "id" => "c7f893648f656339f62fb7b4d8a6ecdf7d063835",
                  "type" => "invalid"
                }
              ]
            }.to_json
          end

          it "raises an error" do
            expect { search_commits.call(repository_url, commits) }
              .to raise_error(
                Datadog::CI::Git::SearchCommits::ApiError,
                "Invalid commit type response {\"id\"=>\"c7f893648f656339f62fb7b4d8a6ecdf7d063835\", \"type\"=>\"invalid\"}"
              )
          end
        end

        context "when the response contains an invalid commit SHA" do
          let(:response_payload) do
            {
              "data" => [
                {
                  "id" => "INVALID_SHA",
                  "type" => "commit"
                }
              ]
            }.to_json
          end

          it "raises an error" do
            expect { search_commits.call(repository_url, commits) }
              .to raise_error(Datadog::CI::Git::SearchCommits::ApiError, "Invalid commit SHA response INVALID_SHA")
          end
        end

        context "when the response is not a valid JSON" do
          let(:response_payload) { "invalid json" }

          it "raises an error" do
            expect { search_commits.call(repository_url, commits) }
              .to raise_error(
                Datadog::CI::Git::SearchCommits::ApiError,
                "Failed to parse search commits response: unexpected token at 'invalid json'. Payload was: invalid json"
              )
          end
        end

        context "when the response is missing the data key" do
          let(:response_payload) { {}.to_json }

          it "raises an error" do
            expect { search_commits.call(repository_url, commits) }
              .to raise_error(
                Datadog::CI::Git::SearchCommits::ApiError,
                "Malformed search commits response: key not found: \"data\". Payload was: {}"
              )
          end
        end

        context "when the response is missing the commit type" do
          let(:response_payload) do
            {
              "data" => [
                {
                  "id" => "c7f893648f656339f62fb7b4d8a6ecdf7d063835"
                }
              ]
            }.to_json
          end

          it "raises an error" do
            expect { search_commits.call(repository_url, commits) }
              .to raise_error(
                Datadog::CI::Git::SearchCommits::ApiError,
                "Invalid commit type response {\"id\"=>\"c7f893648f656339f62fb7b4d8a6ecdf7d063835\"}"
              )
          end
        end
      end
    end
  end
end
