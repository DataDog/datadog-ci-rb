# frozen_string_literal: true

require_relative "base"
require_relative "../../../utils/git"

module Datadog
  module CI
    module Ext
      module Environment
        module Providers
          # As a fallback we try to fetch git information from the local git repository
          class LocalGit < Base
            def git_repository_url
              Utils::Git.exec_git_command("git ls-remote --get-url")
            rescue => e
              Datadog.logger.debug(
                "Unable to read git repository url: #{e.class.name} #{e.message} at #{Array(e.backtrace).first}"
              )
              nil
            end

            def git_commit_sha
              Utils::Git.exec_git_command("git rev-parse HEAD")
            rescue => e
              Datadog.logger.debug(
                "Unable to read git commit SHA: #{e.class.name} #{e.message} at #{Array(e.backtrace).first}"
              )
              nil
            end

            def git_branch
              Utils::Git.exec_git_command("git rev-parse --abbrev-ref HEAD")
            rescue => e
              Datadog.logger.debug(
                "Unable to read git branch: #{e.class.name} #{e.message} at #{Array(e.backtrace).first}"
              )
              nil
            end

            def git_tag
              Utils::Git.exec_git_command("git tag --points-at HEAD")
            rescue => e
              Datadog.logger.debug(
                "Unable to read git tag: #{e.class.name} #{e.message} at #{Array(e.backtrace).first}"
              )
              nil
            end

            def git_commit_message
              Utils::Git.exec_git_command("git show -s --format=%s")
            rescue => e
              Datadog.logger.debug(
                "Unable to read git commit message: #{e.class.name} #{e.message} at #{Array(e.backtrace).first}"
              )
              nil
            end

            def git_commit_author_name
              author.name
            end

            def git_commit_author_email
              author.email
            end

            def git_commit_author_date
              author.date
            end

            def git_commit_committer_name
              committer.name
            end

            def git_commit_committer_email
              committer.email
            end

            def git_commit_committer_date
              committer.date
            end

            def workspace_path
              Utils::Git.exec_git_command("git rev-parse --show-toplevel")
            rescue => e
              Datadog.logger.debug(
                "Unable to read git base directory: #{e.class.name} #{e.message} at #{Array(e.backtrace).first}"
              )
              nil
            end

            private

            def author
              return @author if defined?(@author)

              set_git_commit_users
              @author
            end

            def committer
              return @committer if defined?(@committer)

              set_git_commit_users
              @committer
            end

            def set_git_commit_users
              # Get committer and author information in one command.
              output = Utils::Git.exec_git_command("git show -s --format='%an\t%ae\t%at\t%cn\t%ce\t%ct'")
              unless output
                Datadog.logger.debug(
                  "Unable to read git commit users: git command output is nil"
                )
                @author = @committer = NilUser.new
                return
              end

              author_name, author_email, author_timestamp,
                committer_name, committer_email, committer_timestamp = output.split("\t").each(&:strip!)

              @author = GitUser.new(author_name, author_email, author_timestamp)
              @committer = GitUser.new(committer_name, committer_email, committer_timestamp)
            rescue => e
              Datadog.logger.debug(
                "Unable to read git commit users: #{e.class.name} #{e.message} at #{Array(e.backtrace).first}"
              )
              @author = @committer = NilUser.new
            end

            class GitUser
              attr_reader :name, :email, :timestamp

              def initialize(name, email, timestamp)
                @name = name
                @email = email
                @timestamp = timestamp
              end

              def date
                return nil if timestamp.nil?

                Time.at(timestamp.to_i).utc.to_datetime.iso8601
              end
            end

            class NilUser < GitUser
              def initialize
                super(nil, nil, nil)
              end
            end
          end
        end
      end
    end
  end
end
