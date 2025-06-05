# frozen_string_literal: true

require_relative "base"
require_relative "../local_repository"

module Datadog
  module CI
    module Git
      module BaseBranchShaDetection
        class MergeBaseExtractor < Base
          attr_reader :base_branch

          def initialize(remote_name, source_branch, base_branch)
            super(remote_name, source_branch)

            @base_branch = base_branch
          end

          def call
            check_and_fetch_branch(base_branch, remote_name)

            full_base_branch_name = "#{remote_name}/#{remove_remote_prefix(base_branch, remote_name)}"
            merge_base_sha(full_base_branch_name, source_branch)
          end
        end
      end
    end
  end
end
