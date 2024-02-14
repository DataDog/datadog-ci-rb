# frozen_string_literal: true

module Datadog
  module CI
    module Ext
      module Transport
        DEFAULT_DD_SITE = "datadoghq.com"

        HEADER_DD_API_KEY = "DD-API-KEY"
        HEADER_CONTENT_TYPE = "Content-Type"
        HEADER_CONTENT_ENCODING = "Content-Encoding"
        HEADER_EVP_SUBDOMAIN = "X-Datadog-EVP-Subdomain"
        HEADER_CONTAINER_ID = "Datadog-Container-ID"

        EVP_PROXY_V2_PATH_PREFIX = "/evp_proxy/v2/"
        EVP_PROXY_V4_PATH_PREFIX = "/evp_proxy/v4/"
        EVP_PROXY_PATH_PREFIXES = [EVP_PROXY_V4_PATH_PREFIX, EVP_PROXY_V2_PATH_PREFIX].freeze
        EVP_PROXY_COMPRESSION_SUPPORTED = {
          EVP_PROXY_V4_PATH_PREFIX => true,
          EVP_PROXY_V2_PATH_PREFIX => false
        }

        TEST_VISIBILITY_INTAKE_HOST_PREFIX = "citestcycle-intake"
        TEST_VISIBILITY_INTAKE_PATH = "/api/v2/citestcycle"

        CONTENT_TYPE_MESSAGEPACK = "application/msgpack"
        CONTENT_ENCODING_GZIP = "gzip"
      end
    end
  end
end
