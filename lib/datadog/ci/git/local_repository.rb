# frozen_string_literal: true

require "open3"
require "pathname"
require "set"

require_relative "../ext/telemetry"
require_relative "../utils/command"
require_relative "telemetry"
require_relative "user"

module Datadog
  module CI
    module Git
      module LocalRepository
        class GitCommandExecutionError < StandardError
          attr_reader :output, :command, :status
          def initialize(message, output:, command:, status:)
            super(message)

            @output = output
            @command = command
            @status = status
          end
        end

        COMMAND_RETRY_COUNT = 3
        POSSIBLE_BASE_BRANCHES = %w[main master preprod prod dev development trunk].freeze
        DEFAULT_LIKE_BRANCH_FILTER = /^(#{POSSIBLE_BASE_BRANCHES.join("|")}|release\/.*|hotfix\/.*)$/.freeze

        # these values were set based on internal telemetry
        # all timeouts are in seconds
        UNSHALLOW_TIMEOUT = 500
        LONG_TIMEOUT = 30
        SHORT_TIMEOUT = 3

        def self.root
          return @root if defined?(@root)

          @root = git_root || Dir.pwd
        end

        # ATTENTION: this function is running in a hot path
        # and should be optimized for performance
        def self.relative_to_root(path)
          return "" if path.nil?

          root_path = root
          return path if root_path.nil?

          if File.absolute_path?(path)
            # prefix_index is where the root path ends in the given path
            prefix_index = root_path.size

            # impossible case - absolute paths are returned from code coverage tool that always checks
            # that root is a prefix of the path
            return "" if path.size < prefix_index

            prefix_index += 1 if path[prefix_index] == File::SEPARATOR
            res = path[prefix_index..]
          else
            # prefix_to_root is a difference between the root path and the given path
            if @prefix_to_root == ""
              return path
            elsif @prefix_to_root
              return File.join(@prefix_to_root, path)
            end

            pathname = Pathname.new(File.expand_path(path))
            root_path = Pathname.new(root_path)

            # relative_path_from is an expensive function
            res = pathname.relative_path_from(root_path).to_s

            unless defined?(@prefix_to_root)
              @prefix_to_root = res.gsub(path, "") if res.end_with?(path)
            end
          end

          res || ""
        end

        def self.repository_name
          return @repository_name if defined?(@repository_name)

          git_remote_url = git_repository_url

          # return git repository name from remote url without .git extension
          last_path_segment = git_remote_url.split("/").last if git_remote_url
          @repository_name = last_path_segment.gsub(".git", "") if last_path_segment
          @repository_name ||= current_folder_name
        rescue => e
          log_failure(e, "git repository name")
          @repository_name = current_folder_name
        end

        def self.current_folder_name
          File.basename(root)
        end

        def self.git_repository_url
          Telemetry.git_command(Ext::Telemetry::Command::GET_REPOSITORY)
          # @type var res: String?
          res = nil

          duration_ms = Core::Utils::Time.measure(:float_millisecond) do
            res = exec_git_command("git ls-remote --get-url")
          end

          Telemetry.git_command_ms(Ext::Telemetry::Command::GET_REPOSITORY, duration_ms)
          res
        rescue => e
          log_failure(e, "git repository url")
          telemetry_track_error(e, Ext::Telemetry::Command::GET_REPOSITORY)
          nil
        end

        def self.git_root
          exec_git_command("git rev-parse --show-toplevel")
        rescue => e
          log_failure(e, "git root path")
          nil
        end

        def self.git_commit_sha
          exec_git_command("git rev-parse HEAD")
        rescue => e
          log_failure(e, "git commit sha")
          nil
        end

        def self.git_branch
          Telemetry.git_command(Ext::Telemetry::Command::GET_BRANCH)
          # @type var res: String?
          res = nil

          duration_ms = Core::Utils::Time.measure(:float_millisecond) do
            res = exec_git_command("git rev-parse --abbrev-ref HEAD")
          end

          Telemetry.git_command_ms(Ext::Telemetry::Command::GET_BRANCH, duration_ms)
          res
        rescue => e
          log_failure(e, "git branch")
          telemetry_track_error(e, Ext::Telemetry::Command::GET_BRANCH)
          nil
        end

        def self.git_tag
          exec_git_command("git tag --points-at HEAD")
        rescue => e
          log_failure(e, "git tag")
          nil
        end

        def self.git_commit_message
          exec_git_command("git log -n 1 --format=%B")
        rescue => e
          log_failure(e, "git commit message")
          nil
        end

        def self.git_commit_users
          # Get committer and author information in one command.
          output = exec_git_command("git show -s --format='%an\t%ae\t%at\t%cn\t%ce\t%ct'")
          unless output
            Datadog.logger.debug(
              "Unable to read git commit users: git command output is nil"
            )
            nil_user = NilUser.new
            return [nil_user, nil_user]
          end

          author_name, author_email, author_timestamp,
            committer_name, committer_email, committer_timestamp = output.split("\t").each(&:strip!)

          author = User.new(author_name, author_email, author_timestamp)
          committer = User.new(committer_name, committer_email, committer_timestamp)

          [author, committer]
        rescue => e
          log_failure(e, "git commit users")

          nil_user = NilUser.new
          [nil_user, nil_user]
        end

        # returns maximum of 1000 latest commits in the last month
        def self.git_commits
          Telemetry.git_command(Ext::Telemetry::Command::GET_LOCAL_COMMITS)

          # @type var output: String?
          output = nil

          duration_ms = Core::Utils::Time.measure(:float_millisecond) do
            output = exec_git_command("git log --format=%H -n 1000 --since=\"1 month ago\"", timeout: LONG_TIMEOUT)
          end

          Telemetry.git_command_ms(Ext::Telemetry::Command::GET_LOCAL_COMMITS, duration_ms)

          return [] if output.nil?

          output.split("\n")
        rescue => e
          log_failure(e, "git commits")
          telemetry_track_error(e, Ext::Telemetry::Command::GET_LOCAL_COMMITS)
          []
        end

        def self.git_commits_rev_list(included_commits:, excluded_commits:)
          Telemetry.git_command(Ext::Telemetry::Command::GET_OBJECTS)
          included_commits = filter_invalid_commits(included_commits).join(" ")
          excluded_commits = filter_invalid_commits(excluded_commits).map! { |sha| "^#{sha}" }.join(" ")

          # @type var res: String?
          res = nil

          duration_ms = Core::Utils::Time.measure(:float_millisecond) do
            res = exec_git_command(
              "git rev-list " \
              "--objects " \
              "--no-object-names " \
              "--filter=blob:none " \
              "--since=\"1 month ago\" " \
              "#{excluded_commits} #{included_commits}",
              timeout: LONG_TIMEOUT
            )
          end

          Telemetry.git_command_ms(Ext::Telemetry::Command::GET_OBJECTS, duration_ms)

          res
        rescue => e
          log_failure(e, "git commits rev list")
          telemetry_track_error(e, Ext::Telemetry::Command::GET_OBJECTS)
          nil
        end

        def self.git_generate_packfiles(included_commits:, excluded_commits:, path:)
          return nil unless File.exist?(path)

          commit_tree = git_commits_rev_list(included_commits: included_commits, excluded_commits: excluded_commits)
          return nil if commit_tree.nil?

          basename = SecureRandom.hex(4)

          Telemetry.git_command(Ext::Telemetry::Command::PACK_OBJECTS)

          duration_ms = Core::Utils::Time.measure(:float_millisecond) do
            exec_git_command(
              "git pack-objects --compression=9 --max-pack-size=3m #{path}/#{basename}",
              stdin: commit_tree,
              timeout: LONG_TIMEOUT
            )
          end
          Telemetry.git_command_ms(Ext::Telemetry::Command::PACK_OBJECTS, duration_ms)

          basename
        rescue => e
          log_failure(e, "git generate packfiles")
          telemetry_track_error(e, Ext::Telemetry::Command::PACK_OBJECTS)
          nil
        end

        def self.git_shallow_clone?
          Telemetry.git_command(Ext::Telemetry::Command::CHECK_SHALLOW)
          res = false

          duration_ms = Core::Utils::Time.measure(:float_millisecond) do
            res = exec_git_command("git rev-parse --is-shallow-repository") == "true"
          end
          Telemetry.git_command_ms(Ext::Telemetry::Command::CHECK_SHALLOW, duration_ms)

          res
        rescue => e
          log_failure(e, "git shallow clone")
          telemetry_track_error(e, Ext::Telemetry::Command::CHECK_SHALLOW)
          false
        end

        def self.git_unshallow
          Telemetry.git_command(Ext::Telemetry::Command::UNSHALLOW)
          # @type var res: String?
          res = nil

          unshallow_command =
            "git fetch " \
            "--shallow-since=\"1 month ago\" " \
            "--update-shallow " \
            "--filter=\"blob:none\" " \
            "--recurse-submodules=no " \
            "$(git config --default origin --get clone.defaultRemoteName)"

          unshallow_remotes = [
            "$(git rev-parse HEAD)",
            "$(git rev-parse --abbrev-ref --symbolic-full-name @{upstream})",
            nil
          ]

          duration_ms = Core::Utils::Time.measure(:float_millisecond) do
            unshallow_remotes.each do |remote|
              unshallowing_errored = false

              res =
                begin
                  exec_git_command(
                    "#{unshallow_command} #{remote}",
                    timeout: UNSHALLOW_TIMEOUT
                  )
                rescue => e
                  log_failure(e, "git unshallow")
                  telemetry_track_error(e, Ext::Telemetry::Command::UNSHALLOW)
                  unshallowing_errored = true
                  nil
                end

              break [] unless unshallowing_errored
            end
          end

          Telemetry.git_command_ms(Ext::Telemetry::Command::UNSHALLOW, duration_ms)
          res
        end

        # Returns a Set of normalized file paths changed since the given base_commit.
        # If base_commit is nil, returns nil. On error, returns nil.
        def self.get_changed_files_from_diff(base_commit)
          return nil if base_commit.nil?

          Datadog.logger.debug { "calculating git diff from base_commit: #{base_commit}" }

          Telemetry.git_command(Ext::Telemetry::Command::DIFF)

          begin
            # 1. Run the git diff command

            # @type var output: String?
            output = nil
            duration_ms = Core::Utils::Time.measure(:float_millisecond) do
              output = exec_git_command("git diff -U0 --word-diff=porcelain #{base_commit} HEAD", timeout: LONG_TIMEOUT)
            end
            Telemetry.git_command_ms(Ext::Telemetry::Command::DIFF, duration_ms)

            Datadog.logger.debug { "git diff output: #{output}" }

            return nil if output.nil?

            # 2. Parse the output to extract which files changed
            changed_files = Set.new
            output.each_line do |line|
              # Match lines like: diff --git a/foo/bar.rb b/foo/bar.rb
              # This captures git changes on file level
              match = /^diff --git a\/(?<file>.+) b\/(?<file2>.+)$/.match(line)
              if match && match[:file]
                changed_file = match[:file]
                # Normalize to repo root
                normalized_changed_file = relative_to_root(changed_file)
                changed_files << normalized_changed_file unless normalized_changed_file.nil? || normalized_changed_file.empty?

                Datadog.logger.debug { "matched changed_file: #{changed_file} from line: #{line}" }
                Datadog.logger.debug { "normalized_changed_file: #{normalized_changed_file}" }
              end
            end
            changed_files
          rescue => e
            telemetry_track_error(e, Ext::Telemetry::Command::DIFF)
            log_failure(e, "get changed files from diff")
            nil
          end
        end

        # On best effort basis determines the git sha of the most likely
        # base branch for the current PR.
        def self.base_commit_sha(base_branch: nil)
          Telemetry.git_command(Ext::Telemetry::Command::BASE_COMMIT_SHA)

          remote_name = get_remote_name
          Datadog.logger.debug { "Remote name: '#{remote_name}'" }

          Datadog.logger.debug { "Base branch: '#{base_branch}'" }

          source_branch = get_source_branch
          return nil if source_branch.nil?

          Datadog.logger.debug { "Source branch: '#{source_branch}'" }

          possible_base_branches = base_branch.nil? ? POSSIBLE_BASE_BRANCHES : [base_branch]
          # Check and fetch base branches if they don't exist in local git repository
          check_and_fetch_base_branches(possible_base_branches, remote_name)

          default_branch = detect_default_branch(remote_name)
          Datadog.logger.debug { "Default branch: '#{default_branch}'" }

          candidates = build_candidate_list(remote_name, base_branch)
          if candidates.nil? || candidates.empty?
            Datadog.logger.debug { "No candidate branches found." }
            return nil
          end

          metrics = compute_branch_metrics(candidates, source_branch)
          Datadog.logger.debug { "Branch metrics: '#{metrics}'" }

          best_branch_sha = find_best_branch(metrics, default_branch, remote_name)
          Datadog.logger.debug { "Best branch SHA: '#{best_branch_sha}'" }

          best_branch_sha
        rescue => e
          telemetry_track_error(e, Ext::Telemetry::Command::BASE_COMMIT_SHA)
          log_failure(e, "git base ref")
          nil
        end

        def self.check_and_fetch_base_branches(branches, remote_name)
          branches.each do |branch|
            check_and_fetch_branch(branch, remote_name)
          end
        end

        def self.check_and_fetch_branch(branch, remote_name)
          # Check if branch already fetched from remote

          # TODO: branch here could have origin/ prefix already
          exec_git_command("git show-ref --verify --quiet refs/remotes/#{remote_name}/#{branch}")
          Datadog.logger.debug { "Branch '#{remote_name}/#{branch}' already fetched from remote, skipping" }
        rescue GitCommandExecutionError => e
          Datadog.logger.debug { "Branch '#{remote_name}/#{branch}' doesn't exist locally, checking remote..." }

          begin
            remote_heads = exec_git_command("git ls-remote --heads #{remote_name} #{branch}")
            if remote_heads.nil? || remote_heads.empty?
              Datadog.logger.debug { "Branch '#{remote_name}/#{branch}' doesn't exist in remote" }
              return
            end

            Datadog.logger.debug { "Branch '#{remote_name}/#{branch}' exists in remote, fetching" }
            exec_git_command("git fetch --depth 1 #{remote_name} #{branch}", timeout: LONG_TIMEOUT)
          rescue GitCommandExecutionError => e
            Datadog.logger.debug { "Branch '#{remote_name}/#{branch}' couldn't be fetched from remote: #{e}" }
          end
        end

        def self.get_source_branch
          source_branch = exec_git_command("git rev-parse --abbrev-ref HEAD")
          if source_branch.nil?
            Datadog.logger.debug { "Could not get current branch" }
            return nil
          end

          exec_git_command("git rev-parse --verify --quiet #{source_branch} > /dev/null")
          source_branch
        end

        def self.remove_remote_prefix(branch_name, remote_name)
          branch_name&.sub(/^#{Regexp.escape(remote_name)}\//, "")
        end

        def self.main_like_branch?(branch_name, remote_name)
          short_branch_name = remove_remote_prefix(branch_name, remote_name)
          short_branch_name&.match?(DEFAULT_LIKE_BRANCH_FILTER)
        end

        def self.detect_default_branch(remote_name)
          # @type var default_branch: String?
          default_branch = nil
          begin
            default_ref = exec_git_command("git symbolic-ref --quiet --short \"refs/remotes/#{remote_name}/HEAD\" 2>/dev/null")
            default_branch = remove_remote_prefix(default_ref, remote_name) unless default_ref.nil?
          rescue
            Datadog.logger.debug { "Could not get symbolic-ref, trying to find a fallback (main, master)..." }
          end

          default_branch = find_fallback_default_branch(remote_name) if default_branch.nil?
          default_branch
        end

        def self.find_fallback_default_branch(remote_name)
          ["main", "master"].each do |fallback|
            exec_git_command("git show-ref --verify --quiet refs/remotes/#{remote_name}/#{fallback}")
            Datadog.logger.debug { "Found fallback default branch '#{fallback}'" }
            return fallback
          rescue
            next
          end
          nil
        end

        def self.build_candidate_list(remote_name, base_branch)
          # we cannot assume that local branches are the same as remote branches
          # so we need to go over remote branches only
          candidates = exec_git_command("git for-each-ref --format='%(refname:short)' refs/remotes/#{remote_name}")&.lines&.map(&:strip)
          Datadog.logger.debug { "Available branches: '#{candidates}'" }
          candidates&.select! do |candidate_branch|
            # TODO: this "if" might need to be refactored into its own entity
            if base_branch.nil?
              main_like_branch?(candidate_branch, remote_name)
            else
              # TODO: provide a function to compare branches without remote
              remove_remote_prefix(candidate_branch, remote_name) == remove_remote_prefix(base_branch, remote_name)
            end
          end
          Datadog.logger.debug { "Candidate branches: '#{candidates}'" }
          candidates
        end

        def self.compute_branch_metrics(candidates, source_branch)
          metrics = {}
          candidates.each do |cand|
            base_sha = exec_git_command("git merge-base #{cand} #{source_branch} 2>/dev/null", timeout: LONG_TIMEOUT)&.strip
            next if base_sha.nil? || base_sha.empty?

            behind, ahead = exec_git_command("git rev-list --left-right --count #{cand}...#{source_branch}", timeout: LONG_TIMEOUT)&.strip&.split&.map(&:to_i)
            if behind == 0 && ahead == 0
              Datadog.logger.debug { "Branch '#{cand}' is up to date with '#{source_branch}'" }
              next
            end

            metrics[cand] = {behind: behind, ahead: ahead, base_sha: base_sha}
          end
          metrics
        end

        def self.find_best_branch(metrics, default_branch, remote_name)
          return nil if metrics.empty?

          _, best_data = metrics.min_by do |cand, data|
            [
              data[:ahead],
              default_branch?(cand, default_branch, remote_name) ? 0 : 1 # prefer default branch on tie
            ]
          end

          best_data ? best_data[:base_sha] : nil
        end

        def self.default_branch?(branch, default_branch, remote_name)
          branch == default_branch || branch == "#{remote_name}/#{default_branch}"
        end

        def self.get_remote_name
          # Try to find remote from upstream tracking
          upstream = nil
          begin
            upstream = exec_git_command("git rev-parse --abbrev-ref --symbolic-full-name @{upstream}")&.strip
          rescue => e
            Datadog.logger.debug { "Error getting upstream: #{e}" }
          end

          if upstream
            upstream.split("/").first
          else
            # Fallback to first remote if no upstream is set
            first_remote_value = exec_git_command("git remote")&.split("\n")&.first
            Datadog.logger.debug { "First remote value: '#{first_remote_value}'" }
            first_remote_value || "origin"
          end
        end

        class << self
          private

          def filter_invalid_commits(commits)
            commits.filter { |commit| Utils::Git.valid_commit_sha?(commit) }
          end

          def exec_git_command(cmd, stdin: nil, timeout: SHORT_TIMEOUT)
            # @type var out: String
            # @type var status: Process::Status?
            out, status = Utils::Command.exec_command(cmd, stdin_data: stdin, timeout: timeout)

            if status.nil?
              # @type var retry_count: Integer
              retry_count = COMMAND_RETRY_COUNT
              Datadog.logger.debug { "Opening pipe failed, starting retries..." }
              while status.nil? && retry_count.positive?
                out, status = Utils::Command.exec_command(cmd, stdin_data: stdin, timeout: timeout)
                Datadog.logger.debug { "After retry status is [#{status}]" }
                retry_count -= 1
              end
            end

            if status.nil? || !status.success?
              raise GitCommandExecutionError.new(
                "Failed to run git command [#{cmd}] with input [#{stdin}] and output [#{out}]. Status: #{status}",
                output: out,
                command: cmd,
                status: status
              )
            end

            return nil if out.empty?

            out
          end

          def log_failure(e, action)
            Datadog.logger.debug(
              "Unable to perform #{action}: #{e.class.name} #{e.message} at #{Array(e.backtrace).first}"
            )
          end

          def telemetry_track_error(e, command)
            case e
            when Errno::ENOENT
              Telemetry.git_command_errors(command, executable_missing: true)
            when GitCommandExecutionError
              Telemetry.git_command_errors(command, exit_code: e.status&.to_i)
            else
              Telemetry.git_command_errors(command, exit_code: -9000)
            end
          end
        end
      end
    end
  end
end
