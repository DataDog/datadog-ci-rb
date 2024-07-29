# frozen_string_literal: true

require "json"
require "securerandom"

require_relative "../ext/transport"
require_relative "../ext/telemetry"
require_relative "../transport/telemetry"
require_relative "../utils/telemetry"

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

          Transport::Telemetry.api_requests(
            Ext::Telemetry::METRIC_GIT_REQUESTS_OBJECT_PACK,
            1,
            compressed: http_response.request_compressed
          )
          Utils::Telemetry.distribution(Ext::Telemetry::METRIC_GIT_REQUESTS_OBJECT_PACK_MS, http_response.duration_ms)
          Utils::Telemetry.distribution(Ext::Telemetry::METRIC_GIT_REQUESTS_OBJECT_PACK_BYTES, http_response.request_size.to_f)

          unless http_response.ok?
            Transport::Telemetry.api_requests_errors(
              Ext::Telemetry::METRIC_GIT_REQUESTS_OBJECT_PACK_ERRORS,
              1,
              error_type: http_response.telemetry_error_type,
              status_code: http_response.code
            )
            raise ApiError, "Failed to upload packfile: #{http_response.inspect}"
          end
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
