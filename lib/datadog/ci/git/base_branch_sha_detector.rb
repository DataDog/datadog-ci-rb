# frozen_string_literal: true

require_relative "base_branch_sha_detection/guesser"
require_relative "base_branch_sha_detection/merge_base_extractor"

module Datadog
  module CI
    module Git
      module BaseBranchShaDetector
        def self.base_branch_sha(base_branch)
          Datadog.logger.debug { "Base branch: '#{base_branch}'" }

          remote_name = LocalRepository.get_remote_name
          Datadog.logger.debug { "Remote name: '#{remote_name}'" }

          source_branch = get_source_branch
          return nil if source_branch.nil?

          Datadog.logger.debug { "Source branch: '#{source_branch}'" }

          strategy = if base_branch.nil?
            BaseBranchShaDetection::Guesser.new(remote_name, source_branch)
          else
            BaseBranchShaDetection::MergeBaseExtractor.new(remote_name, source_branch, base_branch)
          end

          strategy.call
        end

        def self.get_source_branch
          source_branch = CLI.exec_git_command(["rev-parse", "--abbrev-ref", "HEAD"])
          if source_branch.nil?
            Datadog.logger.debug { "Could not get current branch" }
            return nil
          end

          # Verify the branch exists
          begin
            CLI.exec_git_command(["rev-parse", "--verify", "--quiet", source_branch])
          rescue CLI::GitCommandExecutionError
            # Branch verification failed
            return nil
          end
          source_branch
        end
      end
    end
  end
end
