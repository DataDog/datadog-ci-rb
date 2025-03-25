# frozen_string_literal: true

require "open3"
require "pathname"

require_relative "../ext/telemetry"
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
              @prefix_to_root = res&.gsub(path, "") if res.end_with?(path)
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

          output = nil
          duration_ms = Core::Utils::Time.measure(:float_millisecond) do
            output = exec_git_command("git log --format=%H -n 1000 --since=\"1 month ago\"")
          end

          Telemetry.git_command_ms(Ext::Telemetry::Command::GET_LOCAL_COMMITS, duration_ms)

          return [] if output.nil?

          # @type var output: String
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

          res = nil

          duration_ms = Core::Utils::Time.measure(:float_millisecond) do
            res = exec_git_command(
              "git rev-list " \
              "--objects " \
              "--no-object-names " \
              "--filter=blob:none " \
              "--since=\"1 month ago\" " \
              "#{excluded_commits} #{included_commits}"
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
              stdin: commit_tree
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
                    "#{unshallow_command} #{remote}"
                  )
                rescue => e
                  log_failure(e, "git unshallow")
                  telemetry_track_error(e, Ext::Telemetry::Command::UNSHALLOW)
                  unshallowing_errored = true
                  nil
                end

              break unless unshallowing_errored
            end
          end

          Telemetry.git_command_ms(Ext::Telemetry::Command::UNSHALLOW, duration_ms)
          res
        end

        # makes .exec_git_command private to make sure that this method
        # is not called from outside of this module with insecure parameters
        class << self
          private

          def filter_invalid_commits(commits)
            commits.filter { |commit| Utils::Git.valid_commit_sha?(commit) }
          end

          def exec_git_command(cmd, stdin: nil)
            # Shell injection is alleviated by making sure that no outside modules call this method.
            # It is called only internally with static parameters.
            # no-dd-sa:ruby-security/shell-injection
            out, status = Open3.capture2e(cmd, stdin_data: stdin)

            if status.nil?
              retry_count = COMMAND_RETRY_COUNT
              Datadog.logger.debug { "Opening pipe failed, starting retries..." }
              while status.nil? && retry_count.positive?
                # no-dd-sa:ruby-security/shell-injection
                out, status = Open3.capture2e(cmd, stdin_data: stdin)
                Datadog.logger.debug { "After retry status is [#{status}]" }
                retry_count -= 1
              end
            end

            if status.nil? || !status.success?
              raise GitCommandExecutionError.new(
                "Failed to run git command [#{cmd}] with input [#{stdin}] and output [#{out}]",
                output: out,
                command: cmd,
                status: status
              )
            end

            # Sometimes Encoding.default_external is somehow set to US-ASCII which breaks
            # commit messages with UTF-8 characters like emojis
            # We force output's encoding to be UTF-8 in this case
            # This is safe to do as UTF-8 is compatible with US-ASCII
            if Encoding.default_external == Encoding::US_ASCII
              out = out.force_encoding(Encoding::UTF_8)
            end
            out.strip! # There's always a "\n" at the end of the command output

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
