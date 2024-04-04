# frozen_string_literal: true

require_relative "base"
require_relative "../../../git/local_repository"

module Datadog
  module CI
    module Ext
      module Environment
        module Providers
          # As a fallback we try to fetch git information from the local git repository
          class LocalGit < Base
            def git_repository_url
              CI::Git::LocalRepository.git_repository_url
            end

            def git_commit_sha
              CI::Git::LocalRepository.git_commit_sha
            end

            def git_branch
              CI::Git::LocalRepository.git_branch
            end

            def git_tag
              CI::Git::LocalRepository.git_tag
            end

            def git_commit_message
              CI::Git::LocalRepository.git_commit_message
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
              CI::Git::LocalRepository.git_root
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
              @author, @committer = CI::Git::LocalRepository.git_commit_users
            end
          end
        end
      end
    end
  end
end
