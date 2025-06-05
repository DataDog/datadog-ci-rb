# frozen_string_literal: true

require_relative "../cli"

module Datadog
  module CI
    module Git
      module BaseBranchShaDetection
        class Base
          attr_reader :remote_name
          attr_reader :source_branch

          def initialize(remote_name, source_branch)
            @remote_name = remote_name
            @source_branch = source_branch
          end

          def call
            raise NotImplementedError, "Subclasses must implement #call"
          end

          protected

          def merge_base_sha(branch, source_branch)
            CLI.exec_git_command(["merge-base", branch, source_branch], timeout: CLI::LONG_TIMEOUT)&.strip
          rescue CLI::GitCommandExecutionError => e
            Datadog.logger.debug { "Merge base calculation failed for branches '#{branch}' and '#{source_branch}': #{e}" }
            nil
          end

          def check_and_fetch_branch(branch, remote_name)
            # @type var short_branch_name: String
            short_branch_name = remove_remote_prefix(branch, remote_name)

            # Check if branch already fetched from remote
            CLI.exec_git_command(["show-ref", "--verify", "--quiet", "refs/remotes/#{remote_name}/#{short_branch_name}"])
            Datadog.logger.debug { "Branch '#{remote_name}/#{short_branch_name}' already fetched from remote, skipping" }
          rescue CLI::GitCommandExecutionError => e
            Datadog.logger.debug { "Branch '#{remote_name}/#{short_branch_name}' doesn't exist locally, checking remote..." }

            begin
              remote_heads = CLI.exec_git_command(["ls-remote", "--heads", remote_name, short_branch_name])
              if remote_heads.nil? || remote_heads.empty?
                Datadog.logger.debug { "Branch '#{remote_name}/#{short_branch_name}' doesn't exist in remote" }
                return
              end

              Datadog.logger.debug { "Branch '#{remote_name}/#{short_branch_name}' exists in remote, fetching" }
              CLI.exec_git_command(["fetch", "--depth", "1", remote_name, short_branch_name], timeout: CLI::LONG_TIMEOUT)
            rescue CLI::GitCommandExecutionError => e
              Datadog.logger.debug { "Branch '#{remote_name}/#{short_branch_name}' couldn't be fetched from remote: #{e}" }
            end
          end

          def remove_remote_prefix(branch_name, remote_name)
            branch_name&.sub(/^#{Regexp.escape(remote_name)}\//, "")
          end

          def branches_equal?(branch_name, default_branch, remote_name)
            remove_remote_prefix(branch_name, remote_name) == remove_remote_prefix(default_branch, remote_name)
          end
        end
      end
    end
  end
end
