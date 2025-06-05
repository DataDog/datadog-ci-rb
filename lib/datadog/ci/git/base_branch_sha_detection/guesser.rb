# frozen_string_literal: true

require_relative "base"
require_relative "branch_metric"

require_relative "../local_repository"

module Datadog
  module CI
    module Git
      module BaseBranchShaDetection
        class Guesser < Base
          POSSIBLE_BASE_BRANCHES = %w[main master preprod prod dev development trunk].freeze
          DEFAULT_LIKE_BRANCH_FILTER = /^(#{POSSIBLE_BASE_BRANCHES.join("|")}|release\/.*|hotfix\/.*)$/.freeze

          def call
            # Check and fetch base branches if they don't exist in local git repository
            check_and_fetch_base_branches(POSSIBLE_BASE_BRANCHES, remote_name)

            candidates = build_candidate_list(remote_name)

            if candidates.nil? || candidates.empty?
              Datadog.logger.debug { "No candidate branches found." }
              return nil
            end

            metrics = compute_branch_metrics(candidates, source_branch)
            Datadog.logger.debug { "Branch metrics: '#{metrics}'" }

            best_branch_sha = find_best_branch(metrics, remote_name)
            Datadog.logger.debug { "Best branch SHA: '#{best_branch_sha}'" }

            best_branch_sha
          end

          private

          def check_and_fetch_base_branches(branches, remote_name)
            branches.each do |branch|
              check_and_fetch_branch(branch, remote_name)
            end
          end

          def main_like_branch?(branch_name, remote_name)
            short_branch_name = remove_remote_prefix(branch_name, remote_name)
            short_branch_name&.match?(DEFAULT_LIKE_BRANCH_FILTER)
          end

          def detect_default_branch(remote_name)
            # @type var default_branch: String?
            default_branch = nil
            begin
              default_ref = CLI.exec_git_command(["symbolic-ref", "--quiet", "--short", "refs/remotes/#{remote_name}/HEAD"])
              default_branch = remove_remote_prefix(default_ref, remote_name) unless default_ref.nil?
            rescue
              Datadog.logger.debug { "Could not get symbolic-ref, trying to find a fallback (main, master)..." }
            end

            default_branch = find_fallback_default_branch(remote_name) if default_branch.nil?
            default_branch
          end

          def find_fallback_default_branch(remote_name)
            ["main", "master"].each do |fallback|
              CLI.exec_git_command(["show-ref", "--verify", "--quiet", "refs/remotes/#{remote_name}/#{fallback}"])
              Datadog.logger.debug { "Found fallback default branch '#{fallback}'" }
              return fallback
            rescue
              next
            end
            nil
          end

          def build_candidate_list(remote_name)
            # we cannot assume that local branches are the same as remote branches
            # so we need to go over remote branches only
            candidates = CLI.exec_git_command(["for-each-ref", "--format=%(refname:short)", "refs/remotes/#{remote_name}"])&.lines&.map(&:strip)
            Datadog.logger.debug { "Available branches: '#{candidates}'" }
            candidates&.select! do |candidate_branch|
              main_like_branch?(candidate_branch, remote_name)
            end
            Datadog.logger.debug { "Candidate branches: '#{candidates}'" }
            candidates
          end

          def compute_branch_metrics(candidates, source_branch)
            metrics = []
            candidates.each do |cand|
              base_sha = merge_base_sha(cand, source_branch)
              next if base_sha.nil? || base_sha.empty?

              rev_list_output = CLI.exec_git_command(["rev-list", "--left-right", "--count", "#{cand}...#{source_branch}"], timeout: CLI::LONG_TIMEOUT)&.strip
              next if rev_list_output.nil?

              behind, ahead = rev_list_output.split.map(&:to_i)
              next if behind.nil? || ahead.nil?

              metric = BranchMetric.new(
                branch_name: cand,
                behind: behind,
                ahead: ahead,
                base_sha: base_sha
              )

              if metric.up_to_date?
                Datadog.logger.debug { "Branch '#{cand}' is up to date with '#{source_branch}'" }
                next
              end

              metrics << metric
            end
            metrics
          end

          def find_best_branch(metrics, remote_name)
            return nil if metrics.empty?

            # If there's only one metric, return its base SHA
            return metrics.first.base_sha if metrics.size == 1

            default_branch = detect_default_branch(remote_name)
            Datadog.logger.debug { "Default branch: '#{default_branch}'" }

            best_metric = metrics.min_by do |metric|
              [
                metric.divergence_score,
                branches_equal?(metric.branch_name, default_branch, remote_name) ? 0 : 1 # prefer default branch on tie
              ]
            end

            best_metric&.base_sha
          end
        end
      end
    end
  end
end
