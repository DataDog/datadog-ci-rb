# frozen_string_literal: true

module Datadog
  module CI
    module Contrib
      module RSpec
        # RSpec integration constants
        # TODO: mark as `@public_api` when GA, to protect from resource and tag name changes.
        module Ext
          FRAMEWORK = "rspec"
          DEFAULT_SERVICE_NAME = "rspec"

          ENV_ENABLED = "DD_TRACE_RSPEC_ENABLED"

          # Metadata keys
          METADATA_DD_RETRIES = :dd_retries
          METADATA_DD_RETRY_RESULTS = :dd_retry_results
          METADATA_DD_RETRY_REASON = :dd_retry_reason
          METADATA_DD_QUARANTINED = :dd_quarantined
          METADATA_DD_DISABLED = :dd_disabled
          METADATA_DD_SKIPPED_BY_ITR = :dd_skipped_by_itr
        end
      end
    end
  end
end
