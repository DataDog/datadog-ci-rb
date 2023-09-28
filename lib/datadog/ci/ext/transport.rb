# frozen_string_literal: true

module Datadog
  module CI
    module Ext
      module Transport
        HEADER_DD_API_KEY = "DD-API-KEY"
        HEADER_CONTENT_TYPE = "Content-Type"
        HEADER_CONTENT_ENCODING = "Content-Encoding"

        TEST_VISIBILITY_INTAKE_HOST_PREFIX = "citestcycle-intake"
        TEST_VISIBILITY_INTAKE_PATH = "/api/v2/citestcycle"

        CONTENT_TYPE_MESSAGEPACK = "application/msgpack"
        CONTENT_ENCODING_GZIP = "gzip"
      end
    end
  end
end
