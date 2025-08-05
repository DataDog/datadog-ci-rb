# frozen_string_literal: true

module Datadog
  module CI
    module Ext
      # Defines constants for Git tags
      module Git
        SHA_LENGTH = 40

        TAG_BRANCH = "git.branch"
        TAG_REPOSITORY_URL = "git.repository_url"
        TAG_TAG = "git.tag"

        TAG_COMMIT_AUTHOR_DATE = "git.commit.author.date"
        TAG_COMMIT_AUTHOR_EMAIL = "git.commit.author.email"
        TAG_COMMIT_AUTHOR_NAME = "git.commit.author.name"
        TAG_COMMIT_COMMITTER_DATE = "git.commit.committer.date"
        TAG_COMMIT_COMMITTER_EMAIL = "git.commit.committer.email"
        TAG_COMMIT_COMMITTER_NAME = "git.commit.committer.name"
        TAG_COMMIT_MESSAGE = "git.commit.message"
        TAG_COMMIT_SHA = "git.commit.sha"

        # additional tags that we use for github actions jobs with "pull_request" target
        TAG_PULL_REQUEST_BASE_BRANCH = "git.pull_request.base_branch"
        TAG_PULL_REQUEST_BASE_BRANCH_SHA = "git.pull_request.base_branch_sha"
        TAG_PULL_REQUEST_BASE_BRANCH_HEAD_SHA = "git.pull_request.base_branch_head_sha"

        TAG_COMMIT_HEAD_SHA = "git.commit.head.sha"
        TAG_COMMIT_HEAD_MESSAGE = "git.commit.head.message"
        TAG_COMMIT_HEAD_AUTHOR_DATE = "git.commit.head.author.date"
        TAG_COMMIT_HEAD_AUTHOR_EMAIL = "git.commit.head.author.email"
        TAG_COMMIT_HEAD_AUTHOR_NAME = "git.commit.head.author.name"
        TAG_COMMIT_HEAD_COMMITTER_DATE = "git.commit.head.committer.date"
        TAG_COMMIT_HEAD_COMMITTER_EMAIL = "git.commit.head.committer.email"
        TAG_COMMIT_HEAD_COMMITTER_NAME = "git.commit.head.committer.name"

        ENV_REPOSITORY_URL = "DD_GIT_REPOSITORY_URL"
        ENV_COMMIT_SHA = "DD_GIT_COMMIT_SHA"
        ENV_BRANCH = "DD_GIT_BRANCH"
        ENV_TAG = "DD_GIT_TAG"
        ENV_COMMIT_MESSAGE = "DD_GIT_COMMIT_MESSAGE"
        ENV_COMMIT_AUTHOR_NAME = "DD_GIT_COMMIT_AUTHOR_NAME"
        ENV_COMMIT_AUTHOR_EMAIL = "DD_GIT_COMMIT_AUTHOR_EMAIL"
        ENV_COMMIT_AUTHOR_DATE = "DD_GIT_COMMIT_AUTHOR_DATE"
        ENV_COMMIT_COMMITTER_NAME = "DD_GIT_COMMIT_COMMITTER_NAME"
        ENV_COMMIT_COMMITTER_EMAIL = "DD_GIT_COMMIT_COMMITTER_EMAIL"
        ENV_COMMIT_COMMITTER_DATE = "DD_GIT_COMMIT_COMMITTER_DATE"
        ENV_PULL_REQUEST_BASE_BRANCH = "DD_GIT_PULL_REQUEST_BASE_BRANCH"
        ENV_PULL_REQUEST_BASE_BRANCH_SHA = "DD_GIT_PULL_REQUEST_BASE_BRANCH_SHA"
        ENV_COMMIT_HEAD_SHA = "DD_GIT_COMMIT_HEAD_SHA"
      end
    end
  end
end
