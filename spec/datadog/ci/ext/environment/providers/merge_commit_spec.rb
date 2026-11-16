# frozen_string_literal: true

require "spec_helper"

RSpec.describe "CI merge commit metadata" do
  sha = "a" * 40
  cases = [
    ["GitHub PR merge ref", {"GITHUB_SHA" => sha, "GITHUB_REF" => "refs/pull/12/merge"}, true],
    ["GitHub branch", {"GITHUB_SHA" => sha, "GITHUB_REF" => "refs/heads/feature"}, false],
    ["GitHub PR head ref", {"GITHUB_SHA" => sha, "GITHUB_REF" => "refs/pull/12/head"}, false],
    ["GitHub invalid SHA", {"GITHUB_SHA" => "invalid", "GITHUB_REF" => "refs/pull/12/merge"}, false],
    ["GitLab merged result", {"GITLAB_CI" => "true", "CI_COMMIT_SHA" => sha,
                              "CI_MERGE_REQUEST_IID" => "12", "CI_MERGE_REQUEST_EVENT_TYPE" => "merged_result"}, true],
    ["GitLab merge train", {"GITLAB_CI" => "true", "CI_COMMIT_SHA" => sha,
                            "CI_MERGE_REQUEST_IID" => "12", "CI_MERGE_REQUEST_EVENT_TYPE" => "merge_train"}, true],
    ["GitLab detached MR", {"GITLAB_CI" => "true", "CI_COMMIT_SHA" => sha,
                            "CI_MERGE_REQUEST_IID" => "12", "CI_MERGE_REQUEST_EVENT_TYPE" => "detached"}, false],
    ["Azure PR merge ref", {"TF_BUILD" => "true", "BUILD_SOURCEVERSION" => sha,
                            "BUILD_REASON" => "PullRequest", "BUILD_SOURCEBRANCH" => "refs/pull/12/merge"}, true],
    ["Azure branch", {"TF_BUILD" => "true", "BUILD_SOURCEVERSION" => sha,
                      "BUILD_REASON" => "IndividualCI", "BUILD_SOURCEBRANCH" => "refs/heads/feature"}, false],
    ["AppVeyor PR merge", {"APPVEYOR" => "true", "APPVEYOR_REPO_PROVIDER" => "github", "APPVEYOR_REPO_COMMIT" => sha,
                           "APPVEYOR_PULL_REQUEST_NUMBER" => "12", "APPVEYOR_PULL_REQUEST_HEAD_COMMIT" => "b" * 40}, true],
    ["AppVeyor branch", {"APPVEYOR" => "true", "APPVEYOR_REPO_PROVIDER" => "github", "APPVEYOR_REPO_COMMIT" => sha,
                         "APPVEYOR_PULL_REQUEST_HEAD_COMMIT" => "b" * 40}, false],
    ["AppVeyor PR head checkout", {"APPVEYOR" => "true", "APPVEYOR_REPO_PROVIDER" => "github", "APPVEYOR_REPO_COMMIT" => sha,
                                   "APPVEYOR_PULL_REQUEST_NUMBER" => "12", "APPVEYOR_PULL_REQUEST_HEAD_COMMIT" => sha.upcase}, false],
    ["AppVeyor PR without head", {"APPVEYOR" => "true", "APPVEYOR_REPO_PROVIDER" => "github", "APPVEYOR_REPO_COMMIT" => sha,
                                  "APPVEYOR_PULL_REQUEST_NUMBER" => "12"}, false],
    ["AppVeyor invalid head", {"APPVEYOR" => "true", "APPVEYOR_REPO_PROVIDER" => "github", "APPVEYOR_REPO_COMMIT" => sha,
                               "APPVEYOR_PULL_REQUEST_NUMBER" => "12", "APPVEYOR_PULL_REQUEST_HEAD_COMMIT" => "invalid"}, false],
    ["AppVeyor non-GitHub provider", {"APPVEYOR" => "true", "APPVEYOR_REPO_PROVIDER" => "mercurial", "APPVEYOR_REPO_COMMIT" => sha,
                                      "APPVEYOR_PULL_REQUEST_NUMBER" => "12", "APPVEYOR_PULL_REQUEST_HEAD_COMMIT" => "b" * 40}, false],
    ["AppVeyor invalid PR number", {"APPVEYOR" => "true", "APPVEYOR_REPO_PROVIDER" => "github", "APPVEYOR_REPO_COMMIT" => sha,
                                    "APPVEYOR_PULL_REQUEST_NUMBER" => "invalid", "APPVEYOR_PULL_REQUEST_HEAD_COMMIT" => "b" * 40}, false],
    ["Travis PR", {"TRAVIS" => "true", "TRAVIS_COMMIT" => sha,
                   "TRAVIS_EVENT_TYPE" => "pull_request", "TRAVIS_PULL_REQUEST" => "12"}, true],
    ["Travis push", {"TRAVIS" => "true", "TRAVIS_COMMIT" => sha,
                     "TRAVIS_EVENT_TYPE" => "push", "TRAVIS_PULL_REQUEST" => "false"}, false]
  ]
  cases.each do |name, env, merge|
    it "reports a merge SHA only with positive provider evidence: #{name}" do
      tags = Datadog::CI::Ext::Environment::Extractor.new(env).tags
      expect(tags["ci.git.merge_commit_sha"]).to eq(merge ? sha : nil)
    end
  end
end
