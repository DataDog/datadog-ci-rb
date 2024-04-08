# frozen_string_literal: true

require "open3"
require "pathname"

require_relative "user"

module Datadog
  module CI
    module Git
      module LocalRepository
        def self.root
          return @root if defined?(@root)

          @root = git_root || Dir.pwd
        end

        def self.relative_to_root(path)
          return "" if path.nil?

          root_path = root
          return path if root_path.nil?

          path = Pathname.new(File.expand_path(path))
          root_path = Pathname.new(root_path)

          path.relative_path_from(root_path).to_s
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
          exec_git_command("git ls-remote --get-url")
        rescue => e
          log_failure(e, "git repository url")
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
          exec_git_command("git rev-parse --abbrev-ref HEAD")
        rescue => e
          log_failure(e, "git branch")
          nil
        end

        def self.git_tag
          exec_git_command("git tag --points-at HEAD")
        rescue => e
          log_failure(e, "git tag")
          nil
        end

        def self.git_commit_message
          exec_git_command("git show -s --format=%s")
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
          output = exec_git_command("git log --format=%H -n 1000 --since=\"1 month ago\"")
          return [] if output.nil?

          output.split("\n")
        rescue => e
          log_failure(e, "git commits")
          []
        end

        def self.git_commits_rev_list(included_commits:, excluded_commits:)
          included_commits = filter_invalid_commits(included_commits).join(" ")
          excluded_commits = filter_invalid_commits(excluded_commits).map! { |sha| "^#{sha}" }.join(" ")

          exec_git_command(
            "git rev-list " \
            "--objects " \
            "--no-object-names " \
            "--filter=blob:none " \
            "--since=\"1 month ago\" " \
            "#{excluded_commits} #{included_commits}"
          )
        rescue => e
          log_failure(e, "git commits rev list")
          nil
        end

        def self.git_generate_packfiles(included_commits:, excluded_commits:, path:)
          return nil unless File.exist?(path)

          commit_tree = git_commits_rev_list(included_commits: included_commits, excluded_commits: excluded_commits)
          return nil if commit_tree.nil?

          basename = SecureRandom.hex(4)

          exec_git_command(
            "git pack-objects --compression=9 --max-pack-size=3m #{path}/#{basename}",
            stdin: commit_tree
          )
        rescue => e
          log_failure(e, "git generate packfiles")
          nil
        end

        # makes .exec_git_command private to make sure that this method
        # is not called from outside of this module with insecure parameters
        class << self
          private

          def filter_invalid_commits(commits)
            commits.filter_map do |commit|
              next unless Utils::Git.valid_commit_sha?(commit)

              commit
            end
          end

          def exec_git_command(cmd, stdin: nil)
            # Shell injection is alleviated by making sure that no outside modules call this method.
            # It is called only internally with static parameters.
            # no-dd-sa:ruby-security/shell-injection
            out, status = Open3.capture2e(cmd, stdin_data: stdin)

            raise "Failed to run git command #{cmd}: #{out}" unless status.success?

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
              "Unable to read #{action}: #{e.class.name} #{e.message} at #{Array(e.backtrace).first}"
            )
          end
        end
      end
    end
  end
end
