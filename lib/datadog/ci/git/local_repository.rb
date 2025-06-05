# frozen_string_literal: true

require "open3"
require "pathname"
require "set"

require_relative "../ext/telemetry"
require_relative "../utils/command"
require_relative "base_branch_sha_detector"
require_relative "cli"
require_relative "telemetry"
require_relative "user"

module Datadog
  module CI
    module Git
      module LocalRepository
        POSSIBLE_BASE_BRANCHES = %w[main master preprod prod dev development trunk].freeze
        DEFAULT_LIKE_BRANCH_FILTER = /^(#{POSSIBLE_BASE_BRANCHES.join("|")}|release\/.*|hotfix\/.*)$/.freeze

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

        def self.git_commit_message
          CLI.exec_git_command(["log", "-n", "1", "--format=%B"])
        rescue => e
          log_failure(e, "git commit message")
          nil
        end

        def self.git_commit_users
          # Get committer and author information in one command.
          output = CLI.exec_git_command(["show", "-s", "--format=%an\t%ae\t%at\t%cn\t%ce\t%ct"])
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

        def self.git_unshallow
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
          unshallow_remotes << nil # fallback to empty unshallow remote

          duration_ms = Core::Utils::Time.measure(:float_millisecond) do
            unshallow_remotes.each do |remote|
              unshallowing_errored = false

              res =
                begin
                  # @type var cmd: Array[String]
                  cmd = [
                    "fetch",
                    "--shallow-since=\"1 month ago\"",
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
              output = CLI.exec_git_command(["diff", "-U0", "--word-diff=porcelain", base_commit, "HEAD"], timeout: CLI::LONG_TIMEOUT)
            end
            Telemetry.git_command_ms(Ext::Telemetry::Command::DIFF, duration_ms)

            Datadog.logger.debug { "git diff output: #{output}" }

            return nil if output.nil?

            # 2. Parse the output to extract which files changed
            changed_files = Set.new
            output.each_line do |line|
              # Match lines like: diff --git a/foo/bar.rb b/foo/bar.rb
              # This captures git changes on file level
              match = /^diff --git a\/(?<file>.+?) b\//.match(line)
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
            Telemetry.track_error(e, Ext::Telemetry::Command::DIFF)
            log_failure(e, "get changed files from diff")
            nil
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
