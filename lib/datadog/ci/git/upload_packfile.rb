# frozen_string_literal: true

require "json"
require "securerandom"

module Datadog
  module CI
    module Git
      class UploadPackfile
        class ApiError < StandardError; end

        attr_reader :api, :head_commit_sha, :repository_url

        def initialize(api:, head_commit_sha:, repository_url:)
          @api = api
          @head_commit_sha = head_commit_sha
          @repository_url = repository_url
        end

        def call(filepath:)
          raise ApiError, "test visibility API is not configured" if api.nil?

          payload_boundary = SecureRandom.uuid

          filename = File.basename(filepath)
          packfile_contents = read_file(filepath)

          payload = request_payload(payload_boundary, filename, packfile_contents)
          content_type = "#{Ext::Transport::CONTENT_TYPE_MULTIPART_FORM_DATA}; boundary=#{payload_boundary}"

          http_response = api.api_request(
            path: Ext::Transport::DD_API_GIT_UPLOAD_PACKFILE_PATH,
            payload: payload,
            headers: {Ext::Transport::HEADER_CONTENT_TYPE => content_type}
          )

          raise ApiError, "Failed to upload packfile: #{http_response.inspect}" unless http_response.ok?
        end

        private

        def request_payload(boundary, filename, packfile_contents)
          [
            "--#{boundary}",
            'Content-Disposition: form-data; name="pushedSha"',
            "Content-Type: application/json",
            "",
            {data: {id: head_commit_sha, type: "commit"}, meta: {repository_url: repository_url}}.to_json,
            "--#{boundary}",
            "Content-Disposition: form-data; name=\"packfile\"; filename=\"#{filename}\"",
            "Content-Type: application/octet-stream",
            "",
            packfile_contents,
            "--#{boundary}--"
          ].join("\r\n")
        end

        def read_file(filepath)
          File.read(filepath)
        rescue => e
          raise ApiError, "Failed to read packfile: #{e.message}"
        end
      end
    end
  end
end
