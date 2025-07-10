# frozen_string_literal: true

require "open3"
require "pathname"
require "set"

require_relative "../ext/telemetry"
require_relative "../utils/command"
require_relative "base_branch_sha_detector"
require_relative "cli"
require_relative "diff"
require_relative "telemetry"
require_relative "user"

module Datadog
  module CI
    module Git
      module LocalRepository
        def self.root
          return @root if defined?(@root)

          @root = git_root || Dir.pwd
        end

        # ATTENTION: this function is running in a hot path
        # and must be optimized for performance
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

            # this means that the root is not a prefix of this path somehow
            return "" if path[prefix_index] != File::SEPARATOR

            res = path[prefix_index + 1..]
          else
            # prefix_to_root is a difference between the root path and the given path
            if defined?(@prefix_to_root)
              # if path starts with ./ remove the dot before applying the optimization
              # @type var path: String
              path = path[1..] if path.start_with?("./")

              if @prefix_to_root == ""
                return path
              elsif @prefix_to_root
                return File.join(@prefix_to_root, path)
              end
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
            res = CLI.exec_git_command(["ls-remote", "--get-url"])
          end

          Telemetry.git_command_ms(Ext::Telemetry::Command::GET_REPOSITORY, duration_ms)
          res
        rescue => e
          log_failure(e, "git repository url")
          Telemetry.track_error(e, Ext::Telemetry::Command::GET_REPOSITORY)
          nil
        end

        def self.git_root
          CLI.exec_git_command(["rev-parse", "--show-toplevel"])
        rescue => e
          log_failure(e, "git root path")
          nil
        end

        def self.git_commit_sha
          CLI.exec_git_command(["rev-parse", "HEAD"])
        rescue => e
          log_failure(e, "git commit sha")
          nil
        end

        def self.git_branch
          Telemetry.git_command(Ext::Telemetry::Command::GET_BRANCH)
          # @type var res: String?
          res = nil

          duration_ms = Core::Utils::Time.measure(:float_millisecond) do
            res = CLI.exec_git_command(["rev-parse", "--abbrev-ref", "HEAD"])
          end

          Telemetry.git_command_ms(Ext::Telemetry::Command::GET_BRANCH, duration_ms)
          res
        rescue => e
          log_failure(e, "git branch")
          Telemetry.track_error(e, Ext::Telemetry::Command::GET_BRANCH)
          nil
        end

        def self.git_tag
          CLI.exec_git_command(["tag", "--points-at", "HEAD"])
        rescue => e
          log_failure(e, "git tag")
          nil
        end

        def self.git_commit_message(commit_sha = nil)
          CLI.exec_git_command(["log", "-n", "1", "--format=%B", commit_sha].compact)
        rescue => e
          log_failure(e, "git commit message")
          nil
        end

        def self.git_commit_users(commit_sha = nil)
          # Get committer and author information in one command.
          output = CLI.exec_git_command(["show", "-s", "--format=%an\t%ae\t%at\t%cn\t%ce\t%ct", commit_sha].compact)
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
            output = CLI.exec_git_command(["log", "--format=%H", "-n", "1000", "--since=\"1 month ago\""], timeout: CLI::LONG_TIMEOUT)
          end

          Telemetry.git_command_ms(Ext::Telemetry::Command::GET_LOCAL_COMMITS, duration_ms)

          return [] if output.nil?

          output.split("\n")
        rescue => e
          log_failure(e, "git commits")
          Telemetry.track_error(e, Ext::Telemetry::Command::GET_LOCAL_COMMITS)
          []
        end

        def self.git_commits_rev_list(included_commits:, excluded_commits:)
          Telemetry.git_command(Ext::Telemetry::Command::GET_OBJECTS)
          included_commits_list = filter_invalid_commits(included_commits)
          excluded_commits_list = filter_invalid_commits(excluded_commits).map { |sha| "^#{sha}" }

          # @type var res: String?
          res = nil

          duration_ms = Core::Utils::Time.measure(:float_millisecond) do
            cmd = [
              "rev-list",
              "--objects",
              "--no-object-names",
              "--filter=blob:none",
              "--since=\"1 month ago\""
            ] + excluded_commits_list + included_commits_list

            res = CLI.exec_git_command(cmd, timeout: CLI::LONG_TIMEOUT)
          end

          Telemetry.git_command_ms(Ext::Telemetry::Command::GET_OBJECTS, duration_ms)

          res
        rescue => e
          log_failure(e, "git commits rev list")
          Telemetry.track_error(e, Ext::Telemetry::Command::GET_OBJECTS)
          nil
        end

        def self.git_generate_packfiles(included_commits:, excluded_commits:, path:)
          return nil unless File.exist?(path)

          commit_tree = git_commits_rev_list(included_commits: included_commits, excluded_commits: excluded_commits)
          return nil if commit_tree.nil?

          basename = SecureRandom.hex(4)

          Telemetry.git_command(Ext::Telemetry::Command::PACK_OBJECTS)

          duration_ms = Core::Utils::Time.measure(:float_millisecond) do
            CLI.exec_git_command(
              ["pack-objects", "--compression=9", "--max-pack-size=3m", "#{path}/#{basename}"],
              stdin: commit_tree,
              timeout: CLI::LONG_TIMEOUT
            )
          end
          Telemetry.git_command_ms(Ext::Telemetry::Command::PACK_OBJECTS, duration_ms)

          basename
        rescue => e
          log_failure(e, "git generate packfiles")
          Telemetry.track_error(e, Ext::Telemetry::Command::PACK_OBJECTS)
          nil
        end

        def self.git_shallow_clone?
          Telemetry.git_command(Ext::Telemetry::Command::CHECK_SHALLOW)
          res = false

          duration_ms = Core::Utils::Time.measure(:float_millisecond) do
            res = CLI.exec_git_command(["rev-parse", "--is-shallow-repository"]) == "true"
          end
          Telemetry.git_command_ms(Ext::Telemetry::Command::CHECK_SHALLOW, duration_ms)

          res
        rescue => e
          log_failure(e, "git shallow clone")
          Telemetry.track_error(e, Ext::Telemetry::Command::CHECK_SHALLOW)
          false
        end

        def self.git_unshallow(parent_only: false)
          Telemetry.git_command(Ext::Telemetry::Command::UNSHALLOW)
          # @type var res: String?
          res = nil

          default_remote = CLI.exec_git_command(["config", "--default", "origin", "--get", "clone.defaultRemoteName"])&.strip
          head_commit = git_commit_sha
          upstream_branch = get_upstream_branch

          # Build array of remotes to try, filtering out nil values
          unshallow_remotes = []
          unshallow_remotes << head_commit if head_commit
          unshallow_remotes << upstream_branch if upstream_branch
          unshallow_remotes << nil # Ensure the loop runs at least once, even if no valid remotes are available. This acts as a fallback mechanism.

          duration_ms = Core::Utils::Time.measure(:float_millisecond) do
            unshallow_remotes.each do |remote|
              unshallowing_errored = false

              res =
                begin
                  unshallowing_depth = parent_only ? "--deepen=1" : "--shallow-since=\"1 month ago\""
                  # @type var cmd: Array[String]
                  cmd = [
                    "fetch",
                    unshallowing_depth,
                    "--update-shallow",
                    "--filter=blob:none",
                    "--recurse-submodules=no",
                    default_remote
                  ]
                  cmd << remote if remote

                  CLI.exec_git_command(cmd, timeout: CLI::UNSHALLOW_TIMEOUT)
                rescue => e
                  log_failure(e, "git unshallow")
                  Telemetry.track_error(e, Ext::Telemetry::Command::UNSHALLOW)
                  unshallowing_errored = true
                  nil
                end

              # If the command succeeded, break and return the result
              break [] if res && !unshallowing_errored
            end
          end

          Telemetry.git_command_ms(Ext::Telemetry::Command::UNSHALLOW, duration_ms)
          res
        end

        # Returns a Diff object with relative file paths for files that were changed since the given base_commit.
        # If base_commit is nil, returns nil. On error, returns nil.
        def self.get_changes_since(base_commit)
          return Diff.new if base_commit.nil?

          Datadog.logger.debug { "calculating git diff from base_commit: #{base_commit}" }

          Telemetry.git_command(Ext::Telemetry::Command::DIFF)

          begin
            # 1. Run the git diff command

            # @type var output: String?
            output = nil
            duration_ms = Core::Utils::Time.measure(:float_millisecond) do
              output = CLI.exec_git_command(["diff", "-U0", "--word-diff=porcelain", base_commit, "HEAD"], timeout: CLI::LONG_TIMEOUT)
            end
            Telemetry.git_command_ms(Ext::Telemetry::Command::DIFF, duration_ms)

            Datadog.logger.debug { "git diff output: #{output}" }

            return Diff.new if output.nil?

            # 2. Parse the output using Git::Diff
            Diff.parse_diff_output(output)
          rescue => e
            Telemetry.track_error(e, Ext::Telemetry::Command::DIFF)
            log_failure(e, "get changed files from diff")
            Diff.new
          end
        end

        # On best effort basis determines the git sha of the most likely
        # base branch for the current PR.
        def self.base_commit_sha(base_branch: nil)
          Telemetry.git_command(Ext::Telemetry::Command::BASE_COMMIT_SHA)

          BaseBranchShaDetector.base_branch_sha(base_branch)
        rescue => e
          Telemetry.track_error(e, Ext::Telemetry::Command::BASE_COMMIT_SHA)
          log_failure(e, "git base ref")
          nil
        end

        def self.get_upstream_branch
          CLI.exec_git_command(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"])
        rescue => e
          Datadog.logger.debug { "Error getting upstream: #{e}" }
          nil
        end

        def self.filter_invalid_commits(commits)
          commits.filter { |commit| Utils::Git.valid_commit_sha?(commit) }
        end

        def self.log_failure(e, action)
          Datadog.logger.debug(
            "Unable to perform #{action}: #{e.class.name} #{e.message} at #{Array(e.backtrace).first}"
          )
        end
      end
    end
  end
end
