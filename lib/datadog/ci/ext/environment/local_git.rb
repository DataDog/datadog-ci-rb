# frozen_string_literal: true

require "open3"

require_relative "extractor"
require_relative "../git"

module Datadog
  module CI
    module Ext
      module Environment
        # As a fallback we try to fetch git information from the local git repository
        class LocalGit < Extractor
          private

          def git_repository_url
            exec_git_command("git ls-remote --get-url")
          rescue => e
            Datadog.logger.debug(
              "Unable to read git repository url: #{e.class.name} #{e.message} at #{Array(e.backtrace).first}"
            )
            nil
          end

          def git_commit_sha
            exec_git_command("git rev-parse HEAD")
          rescue => e
            Datadog.logger.debug(
              "Unable to read git commit SHA: #{e.class.name} #{e.message} at #{Array(e.backtrace).first}"
            )
            nil
          end

          def git_branch
            exec_git_command("git rev-parse --abbrev-ref HEAD")
          rescue => e
            Datadog.logger.debug(
              "Unable to read git branch: #{e.class.name} #{e.message} at #{Array(e.backtrace).first}"
            )
            nil
          end

          def git_tag
            exec_git_command("git tag --points-at HEAD")
          rescue => e
            Datadog.logger.debug(
              "Unable to read git tag: #{e.class.name} #{e.message} at #{Array(e.backtrace).first}"
            )
            nil
          end

          def git_commit_message
            exec_git_command("git show -s --format=%s")
          rescue => e
            Datadog.logger.debug(
              "Unable to read git commit message: #{e.class.name} #{e.message} at #{Array(e.backtrace).first}"
            )
            nil
          end

          def git_commit_author_name
            git_commit_users[:author_name]
          end

          def git_commit_author_email
            git_commit_users[:author_email]
          end

          def git_commit_author_date
            git_commit_users[:author_date]
          end

          def git_commit_committer_name
            git_commit_users[:committer_name]
          end

          def git_commit_committer_email
            git_commit_users[:committer_email]
          end

          def git_commit_committer_date
            git_commit_users[:committer_date]
          end

          def workspace_path
            exec_git_command("git rev-parse --show-toplevel")
          rescue => e
            Datadog.logger.debug(
              "Unable to read git base directory: #{e.class.name} #{e.message} at #{Array(e.backtrace).first}"
            )
            nil
          end

          # local git specific methods
          def exec_git_command(cmd)
            out, status = Open3.capture2e(cmd)

            raise "Failed to run git command #{cmd}: #{out}" unless status.success?

            out.strip! # There's always a "\n" at the end of the command output

            return nil if out.empty?

            out
          end

          def git_commit_users
            return @commit_users if defined?(@commit_users)

            # Get committer and author information in one command.
            output = exec_git_command("git show -s --format='%an\t%ae\t%at\t%cn\t%ce\t%ct'")
            unless output
              Datadog.logger.debug(
                "Unable to read git commit users: git command output is nil"
              )
              return @commit_users = {}
            end

            fields = output.split("\t").each(&:strip!)

            @commit_users = {
              author_name: fields[0],
              author_email: fields[1],
              # Because we can't get a reliable UTC time from all recent versions of git
              # We have to rely on converting the date to UTC ourselves.
              author_date: Time.at(fields[2].to_i).utc.to_datetime.iso8601,
              committer_name: fields[3],
              committer_email: fields[4],
              # Because we can't get a reliable UTC time from all recent versions of git
              # We have to rely on converting the date to UTC ourselves.
              committer_date: Time.at(fields[5].to_i).utc.to_datetime.iso8601
            }
          rescue => e
            Datadog.logger.debug(
              "Unable to read git commit users: #{e.class.name} #{e.message} at #{Array(e.backtrace).first}"
            )
            @commit_users = {}
          end
        end
      end
    end
  end
end
