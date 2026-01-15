RSpec.describe ::Datadog::CI::Ext::Environment::Providers::GithubActions do
  def with_runner_diag_path(path)
    original_path = described_class::GITHUB_RUNNER_DIAG_PATH
    described_class.send(:remove_const, :GITHUB_RUNNER_DIAG_PATH)
    described_class.const_set(:GITHUB_RUNNER_DIAG_PATH, path)
    yield
  ensure
    described_class.send(:remove_const, :GITHUB_RUNNER_DIAG_PATH)
    described_class.const_set(:GITHUB_RUNNER_DIAG_PATH, original_path)
  end

  describe ".tags" do
    include_context "extract environment tags"

    context "example fixture" do
      let(:env) do
        {
          "GITHUB_ACTION" => "run",
          "GITHUB_JOB" => "github-job-name",
          "GITHUB_REF" => "master",
          "GITHUB_REPOSITORY" => "ghactions-repo",
          "GITHUB_RUN_ID" => "ghactions-pipeline-id",
          "GITHUB_RUN_NUMBER" => "ghactions-pipeline-number",
          "GITHUB_SERVER_URL" => "https://ghenterprise.com",
          "GITHUB_SHA" => "b9f0fb3fdbb94c9d24b2c75b49663122a529e123",
          "GITHUB_WORKFLOW" => "ghactions-pipeline-name",
          "GITHUB_WORKSPACE" => "/foo/bar"
        }
      end

      # Modify HOME so that '~' expansion matches CI home directory.
      let(:environment_variables) { super().merge("HOME" => env["HOME"]) }

      let(:expected_tags) do
        {
          "_dd.ci.env_vars" => "{\"GITHUB_SERVER_URL\":\"https://ghenterprise.com\",\"GITHUB_REPOSITORY\":\"ghactions-repo\",\"GITHUB_RUN_ID\":\"ghactions-pipeline-id\"}",
          "ci.job.id" => "github-job-name",
          "ci.job.name" => "github-job-name",
          "ci.job.url" => "https://ghenterprise.com/ghactions-repo/commit/b9f0fb3fdbb94c9d24b2c75b49663122a529e123/checks",
          "ci.pipeline.id" => "ghactions-pipeline-id",
          "ci.pipeline.name" => "ghactions-pipeline-name",
          "ci.pipeline.number" => "ghactions-pipeline-number",
          "ci.pipeline.url" => "https://ghenterprise.com/ghactions-repo/actions/runs/ghactions-pipeline-id",
          "ci.provider.name" => "github",
          "ci.workspace_path" => "/foo/bar",
          "git.branch" => "master",
          "git.commit.sha" => "b9f0fb3fdbb94c9d24b2c75b49663122a529e123",
          "git.repository_url" => "https://ghenterprise.com/ghactions-repo.git"
        }
      end

      it "matches CI tags" do
        is_expected.to eq(expected_tags)
      end
    end

    context "with numeric job ID from runner diagnostics" do
      let(:env) do
        {
          "GITHUB_ACTION" => "run",
          "GITHUB_JOB" => "github-job-name",
          "GITHUB_REF" => "master",
          "GITHUB_REPOSITORY" => "ghactions-repo",
          "GITHUB_RUN_ID" => "ghactions-pipeline-id",
          "GITHUB_RUN_NUMBER" => "ghactions-pipeline-number",
          "GITHUB_SERVER_URL" => "https://github.com",
          "GITHUB_SHA" => "b9f0fb3fdbb94c9d24b2c75b49663122a529e123",
          "GITHUB_WORKFLOW" => "ghactions-pipeline-name",
          "GITHUB_WORKSPACE" => "/foo/bar"
        }
      end

      let(:expected_tags) do
        {
          "_dd.ci.env_vars" => "{\"GITHUB_SERVER_URL\":\"https://github.com\",\"GITHUB_REPOSITORY\":\"ghactions-repo\",\"GITHUB_RUN_ID\":\"ghactions-pipeline-id\"}",
          "ci.job.id" => "55411116365",
          "ci.job.name" => "github-job-name",
          "ci.job.url" => "https://github.com/ghactions-repo/actions/runs/ghactions-pipeline-id/job/55411116365",
          "ci.pipeline.id" => "ghactions-pipeline-id",
          "ci.pipeline.name" => "ghactions-pipeline-name",
          "ci.pipeline.number" => "ghactions-pipeline-number",
          "ci.pipeline.url" => "https://github.com/ghactions-repo/actions/runs/ghactions-pipeline-id",
          "ci.provider.name" => "github",
          "ci.workspace_path" => "/foo/bar",
          "git.branch" => "master",
          "git.commit.sha" => "b9f0fb3fdbb94c9d24b2c75b49663122a529e123",
          "git.repository_url" => "https://github.com/ghactions-repo.git"
        }
      end

      it "matches CI tags with numeric job ID" do
        with_runner_diag_path("./spec/support/fixtures/github_actions/_diag") do
          is_expected.to eq(expected_tags)
        end
      end
    end
    context "with event.json" do
      let(:env) do
        {
          "GITHUB_ACTION" => "run",
          "GITHUB_JOB" => "github-job-name",
          "GITHUB_REF" => "master",
          "GITHUB_REPOSITORY" => "ghactions-repo",
          "GITHUB_RUN_ATTEMPT" => "ghactions-run-attempt",
          "GITHUB_RUN_ID" => "ghactions-pipeline-id",
          "GITHUB_RUN_NUMBER" => "ghactions-pipeline-number",
          "GITHUB_SERVER_URL" => "https://ghenterprise.com",
          "GITHUB_SHA" => "b9f0fb3fdbb94c9d24b2c75b49663122a529e123",
          "GITHUB_WORKFLOW" => "ghactions-pipeline-name",
          "GITHUB_WORKSPACE" => "/foo/bar",
          "GITHUB_EVENT_PATH" => "./spec/support/fixtures/github_actions/github_event.json",
          "GITHUB_BASE_REF" => "github-base-ref"
        }
      end

      let(:expected_tags) do
        {
          "_dd.ci.env_vars" => "{\"GITHUB_SERVER_URL\":\"https://ghenterprise.com\",\"GITHUB_REPOSITORY\":\"ghactions-repo\",\"GITHUB_RUN_ID\":\"ghactions-pipeline-id\",\"GITHUB_RUN_ATTEMPT\":\"ghactions-run-attempt\"}",
          "ci.job.id" => "github-job-name",
          "ci.job.name" => "github-job-name",
          "ci.job.url" => "https://ghenterprise.com/ghactions-repo/commit/b9f0fb3fdbb94c9d24b2c75b49663122a529e123/checks",
          "ci.pipeline.id" => "ghactions-pipeline-id",
          "ci.pipeline.name" => "ghactions-pipeline-name",
          "ci.pipeline.number" => "ghactions-pipeline-number",
          "ci.pipeline.url" => "https://ghenterprise.com/ghactions-repo/actions/runs/ghactions-pipeline-id/attempts/ghactions-run-attempt",
          "ci.provider.name" => "github",
          "ci.workspace_path" => "/foo/bar",
          "git.branch" => "master",
          "git.commit.sha" => "b9f0fb3fdbb94c9d24b2c75b49663122a529e123",
          "git.repository_url" => "https://ghenterprise.com/ghactions-repo.git",
          "git.commit.head.sha" => "df289512a51123083a8e6931dd6f57bb3883d4c4",
          "git.pull_request.base_branch" => "github-base-ref",
          "git.pull_request.base_branch_head_sha" => "52e0974c74d41160a03d59ddc73bb9f5adab054b",
          "pr.number" => "1"
        }
      end

      it "matches CI tags" do
        is_expected.to eq(expected_tags)
      end
    end

    context "with event.json that does not exist" do
      let(:env) do
        {
          "GITHUB_ACTION" => "run",
          "GITHUB_JOB" => "github-job-name",
          "GITHUB_REF" => "master",
          "GITHUB_REPOSITORY" => "ghactions-repo",
          "GITHUB_RUN_ATTEMPT" => "ghactions-run-attempt",
          "GITHUB_RUN_ID" => "ghactions-pipeline-id",
          "GITHUB_RUN_NUMBER" => "ghactions-pipeline-number",
          "GITHUB_SERVER_URL" => "https://ghenterprise.com",
          "GITHUB_SHA" => "b9f0fb3fdbb94c9d24b2c75b49663122a529e123",
          "GITHUB_WORKFLOW" => "ghactions-pipeline-name",
          "GITHUB_WORKSPACE" => "/foo/bar",
          "GITHUB_EVENT_PATH" => "./spec/support/fixtures/github_actions/no_such_file.json",
          "GITHUB_BASE_REF" => "github-base-ref"
        }
      end

      let(:expected_tags) do
        {
          "_dd.ci.env_vars" => "{\"GITHUB_SERVER_URL\":\"https://ghenterprise.com\",\"GITHUB_REPOSITORY\":\"ghactions-repo\",\"GITHUB_RUN_ID\":\"ghactions-pipeline-id\",\"GITHUB_RUN_ATTEMPT\":\"ghactions-run-attempt\"}",
          "ci.job.id" => "github-job-name",
          "ci.job.name" => "github-job-name",
          "ci.job.url" => "https://ghenterprise.com/ghactions-repo/commit/b9f0fb3fdbb94c9d24b2c75b49663122a529e123/checks",
          "ci.pipeline.id" => "ghactions-pipeline-id",
          "ci.pipeline.name" => "ghactions-pipeline-name",
          "ci.pipeline.number" => "ghactions-pipeline-number",
          "ci.pipeline.url" => "https://ghenterprise.com/ghactions-repo/actions/runs/ghactions-pipeline-id/attempts/ghactions-run-attempt",
          "ci.provider.name" => "github",
          "ci.workspace_path" => "/foo/bar",
          "git.branch" => "master",
          "git.commit.sha" => "b9f0fb3fdbb94c9d24b2c75b49663122a529e123",
          "git.repository_url" => "https://ghenterprise.com/ghactions-repo.git",
          "git.pull_request.base_branch" => "github-base-ref"
        }
      end

      it "matches CI tags" do
        is_expected.to eq(expected_tags)
      end
    end
  end

  describe "#pr_number" do
    subject { described_class.new(env).pr_number }

    context "without event.json" do
      let(:env) do
        {
          "GITHUB_SHA" => "b9f0fb3fdbb94c9d24b2c75b49663122a529e123"
        }
      end

      it { is_expected.to be_nil }
    end

    context "with event.json" do
      let(:env) do
        {
          "GITHUB_SHA" => "b9f0fb3fdbb94c9d24b2c75b49663122a529e123",
          "GITHUB_EVENT_PATH" => "./spec/support/fixtures/github_actions/github_event.json"
        }
      end

      it { is_expected.to eq(1) }
    end

    context "with event.json that does not exist" do
      let(:env) do
        {
          "GITHUB_SHA" => "b9f0fb3fdbb94c9d24b2c75b49663122a529e123",
          "GITHUB_EVENT_PATH" => "./spec/support/fixtures/github_actions/no_such_file.json"
        }
      end

      it { is_expected.to be_nil }
    end

    context "with malformed event.json" do
      let(:env) do
        {
          "GITHUB_SHA" => "b9f0fb3fdbb94c9d24b2c75b49663122a529e123",
          "GITHUB_EVENT_PATH" => "./spec/support/fixtures/github_actions/malformed_event.json"
        }
      end

      before do
        allow(File).to receive(:read).and_return("invalid json")
      end

      it { is_expected.to be_nil }
    end
  end

  describe "#job_id" do
    subject(:job_id) { described_class.new(env).job_id }

    let(:env) do
      {
        "GITHUB_SHA" => "b9f0fb3fdbb94c9d24b2c75b49663122a529e123",
        "GITHUB_JOB" => "github-job-name"
      }
    end

    context "without runner diagnostics" do
      it { is_expected.to eq("github-job-name") }
    end

    context "with runner diagnostics containing numeric job ID" do
      it "returns numeric job ID" do
        with_runner_diag_path("./spec/support/fixtures/github_actions/_diag") do
          expect(job_id).to eq("55411116365")
        end
      end
    end

    context "with non-existent diag path" do
      it "falls back to GITHUB_JOB" do
        with_runner_diag_path("./spec/support/fixtures/github_actions/non_existent_diag") do
          expect(job_id).to eq("github-job-name")
        end
      end
    end

    context "with empty diag directory" do
      before do
        FileUtils.mkdir_p("./spec/support/fixtures/github_actions/_diag_empty")
      end

      after do
        FileUtils.rm_rf("./spec/support/fixtures/github_actions/_diag_empty")
      end

      it "falls back to GITHUB_JOB" do
        with_runner_diag_path("./spec/support/fixtures/github_actions/_diag_empty") do
          expect(job_id).to eq("github-job-name")
        end
      end
    end

    context "with runner diagnostics file that contains no JSON" do
      it "falls back to GITHUB_JOB" do
        with_runner_diag_path("./spec/support/fixtures/github_actions/_diag_no_json") do
          expect(job_id).to eq("github-job-name")
        end
      end
    end

    context "with runner diagnostics file that contains invalid JSON" do
      it "falls back to GITHUB_JOB" do
        with_runner_diag_path("./spec/support/fixtures/github_actions/_diag_invalid_json") do
          expect(job_id).to eq("github-job-name")
        end
      end
    end

    context "with runner diagnostics file that has valid JSON but missing expected data" do
      it "falls back to GITHUB_JOB" do
        with_runner_diag_path("./spec/support/fixtures/github_actions/_diag_missing_data") do
          expect(job_id).to eq("github-job-name")
        end
      end
    end

    context "with runner diagnostics file that is empty" do
      it "falls back to GITHUB_JOB" do
        with_runner_diag_path("./spec/support/fixtures/github_actions/_diag_empty_file") do
          expect(job_id).to eq("github-job-name")
        end
      end
    end
  end

  describe "#job_url" do
    subject(:job_url) { described_class.new(env).job_url }

    let(:env) do
      {
        "GITHUB_SHA" => "b9f0fb3fdbb94c9d24b2c75b49663122a529e123",
        "GITHUB_SERVER_URL" => "https://github.com",
        "GITHUB_REPOSITORY" => "owner/repo",
        "GITHUB_RUN_ID" => "12345"
      }
    end

    context "without runner diagnostics" do
      it { is_expected.to eq("https://github.com/owner/repo/commit/b9f0fb3fdbb94c9d24b2c75b49663122a529e123/checks") }
    end

    context "with runner diagnostics containing numeric job ID" do
      it "returns URL with numeric job ID" do
        with_runner_diag_path("./spec/support/fixtures/github_actions/_diag") do
          expect(job_url).to eq("https://github.com/owner/repo/actions/runs/12345/job/55411116365")
        end
      end
    end
  end
end
