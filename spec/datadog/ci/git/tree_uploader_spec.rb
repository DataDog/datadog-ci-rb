# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/git/tree_uploader"

RSpec.describe Datadog::CI::Git::TreeUploader do
  let(:api) { double("api") }
  subject(:tree_uploader) { described_class.new(api: api) }

  before do
    allow(Datadog.logger).to receive(:debug)
  end

  describe "#call" do
    let(:repository_url) { "https://datadoghq.com/git/test.git" }
    let(:latest_commits) { %w[c7f893648f656339f62fb7b4d8a6ecdf7d063835 13c988d4f15e06bcdd0b0af290086a3079cdadb0] }
    let(:head_commit) { "c7f893648f656339f62fb7b4d8a6ecdf7d063835" }
    let(:backend_commits) { %w[c7f893648f656339f62fb7b4d8a6ecdf7d063835] }

    let(:search_commits) { double("search_commits", call: backend_commits) }

    before do
      allow(Datadog::CI::Git::SearchCommits).to receive(:new).with(api: api).and_return(search_commits)
    end

    context "when the API is not configured" do
      let(:api) { nil }

      it "logs a debug message and aborts the git upload" do
        expect(Datadog.logger).to receive(:debug).with("API is not configured, aborting git upload")

        tree_uploader.call(repository_url)
      end
    end

    context "when API is configured" do
      before do
        expect(Datadog::CI::Git::LocalRepository).to receive(:git_commits).and_return(latest_commits)
      end

      context "when the latest commits list is empty" do
        let(:latest_commits) { [] }

        it "logs a debug message and aborts the git upload" do
          expect(Datadog.logger).to receive(:debug).with("Got empty latest commits list, aborting git upload")

          tree_uploader.call(repository_url)
        end
      end

      context "when the backend commits search fails" do
        before do
          expect(search_commits).to receive(:call).and_raise(Datadog::CI::Git::SearchCommits::ApiError, "test error")
        end

        it "logs a debug message and aborts the git upload" do
          expect(Datadog.logger).to receive(:debug).with("SearchCommits failed with test error, aborting git upload")

          tree_uploader.call(repository_url)
        end
      end

      context "when all commits are known to the backend" do
        let(:backend_commits) { latest_commits }

        it "logs a debug message and aborts the git upload" do
          expect(Datadog.logger).to receive(:debug).with("No new commits to upload")

          tree_uploader.call(repository_url)
        end
      end

      context "when some commits are new" do
        let(:upload_packfile) { double("upload_packfile", call: nil) }

        context "when the repository is shallow cloned" do
          before do
            expect(Datadog::CI::Git::LocalRepository).to receive(:git_shallow_clone?).and_return(true)
          end

          context "when the unshallowing fails" do
            before do
              expect(Datadog::CI::Git::LocalRepository).to receive(:git_unshallow).and_return(nil)
            end

            it "uploads what we can upload" do
              expect(Datadog::CI::Git::Packfiles).to receive(:generate).with(
                included_commits: %w[13c988d4f15e06bcdd0b0af290086a3079cdadb0],
                excluded_commits: backend_commits
              ).and_yield("packfile_path")

              tree_uploader.call(repository_url)
            end
          end

          context "when the unshallowing succeeds" do
            before do
              expect(Datadog::CI::Git::LocalRepository).to receive(:git_unshallow).and_return("unshallow_result")
              expect(Datadog::CI::Git::LocalRepository).to receive(:git_commits).and_return(
                latest_commits + %w[782d09e3fbfd8cf1b5c13f3eb9621362f9089ed5]
              )
            end

            it "uploads the new commits" do
              expect(Datadog::CI::Git::Packfiles).to receive(:generate).with(
                included_commits: %w[13c988d4f15e06bcdd0b0af290086a3079cdadb0 782d09e3fbfd8cf1b5c13f3eb9621362f9089ed5],
                excluded_commits: backend_commits
              ).and_yield("packfile_path")

              tree_uploader.call(repository_url)
            end
          end
        end

        context "when the repository is not shallow cloned" do
          before do
            expect(Datadog::CI::Git::LocalRepository).to receive(:git_shallow_clone?).and_return(false)

            expect(Datadog::CI::Git::Packfiles).to receive(:generate).with(
              included_commits: latest_commits - backend_commits.to_a,
              excluded_commits: backend_commits
            ).and_yield("packfile_path")

            expect(Datadog::CI::Git::UploadPackfile).to receive(:new).with(
              api: api,
              head_commit_sha: head_commit,
              repository_url: repository_url
            ).and_return(upload_packfile)
          end

          context "when the packfile upload fails" do
            before do
              expect(upload_packfile).to receive(:call).and_raise(Datadog::CI::Git::UploadPackfile::ApiError, "test error")
            end

            it "logs a debug message and aborts the git upload" do
              expect(Datadog.logger).to receive(:debug).with("Packfile upload failed with test error")

              tree_uploader.call(repository_url)
            end
          end

          context "when the packfile upload succeeds" do
            it "uploads the new commits" do
              expect(upload_packfile).to receive(:call).with(filepath: "packfile_path").and_return(nil)

              tree_uploader.call(repository_url)
            end
          end
        end
      end
    end
  end
end
