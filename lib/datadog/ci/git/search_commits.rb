# frozen_string_literal: true

require "json"
require "set"

require_relative "../ext/transport"
require_relative "../utils/git"

module Datadog
  module CI
    module Git
      class SearchCommits
        class ApiError < StandardError; end

        attr_reader :api

        def initialize(api:)
          @api = api
        end

        def call(repository_url, commits)
          raise ApiError, "test visibility API is not configured" if api.nil?

          http_response = api.api_request(
            path: Ext::Transport::DD_API_GIT_SEARCH_COMMITS_PATH,
            payload: request_payload(repository_url, commits)
          )
          raise ApiError, "Failed to search commits: #{http_response.inspect}" unless http_response.ok?

          response_payload = parse_json_response(http_response)
          extract_commits(response_payload)
        end

        private

        def request_payload(repository_url, commits)
          {
            meta: {
              repository_url: repository_url
            },
            data: commits.filter_map do |commit|
              next unless Utils::Git.valid_commit_sha?(commit)

              {
                id: commit,
                type: "commit"
              }
            end
          }.to_json
        end

        def parse_json_response(http_response)
          JSON.parse(http_response.payload)
        rescue JSON::ParserError => e
          raise ApiError, "Failed to parse search commits response: #{e}. Payload was: #{http_response.payload}"
        end

        def extract_commits(response_payload)
          result = Set.new

          response_payload.fetch("data").each do |commit_json|
            raise ApiError, "Invalid commit type response #{commit_json}" unless commit_json["type"] == "commit"

            commit_sha = commit_json["id"]
            raise ApiError, "Invalid commit SHA response #{commit_sha}" unless Utils::Git.valid_commit_sha?(commit_sha)

            result.add(commit_sha)
          end

          result
        rescue KeyError => e
          raise ApiError, "Malformed search commits response: #{e}. Payload was: #{response_payload}"
        end
      end
    end
  end
end
