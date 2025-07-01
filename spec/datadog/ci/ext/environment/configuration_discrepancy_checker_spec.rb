# frozen_string_literal: true

require_relative "../../../../../lib/datadog/ci/ext/environment/configuration_discrepancy_checker"

RSpec.describe Datadog::CI::Ext::Environment::ConfigurationDiscrepancyChecker do
  include_context "Telemetry spy"

  let(:ci_provider_env_tags) { {} }
  let(:local_git_tags) { {} }
  let(:user_provided_tags) { {} }

  subject(:checker) do
    described_class.new(ci_provider_env_tags, local_git_tags, user_provided_tags)
  end

  describe "#check_for_discrepancies" do
    let(:commit_sha_1) { "abc123456789012345678901234567890abcdef12" }
    let(:commit_sha_2) { "def456789012345678901234567890abcdef123456" }
    let(:commit_sha_3) { "ghi789012345678901234567890abcdef123456789" }
    let(:repo_url_1) { "https://github.com/user/repo1.git" }
    let(:repo_url_2) { "https://github.com/user/repo2.git" }
    let(:repo_url_3) { "https://github.com/user/repo3.git" }

    context "when all git information matches" do
      let(:ci_provider_env_tags) do
        {
          Datadog::CI::Ext::Git::TAG_COMMIT_SHA => commit_sha_1,
          Datadog::CI::Ext::Git::TAG_REPOSITORY_URL => repo_url_1
        }
      end
      let(:local_git_tags) do
        {
          Datadog::CI::Ext::Git::TAG_COMMIT_SHA => commit_sha_1,
          Datadog::CI::Ext::Git::TAG_REPOSITORY_URL => repo_url_1
        }
      end
      let(:user_provided_tags) do
        {
          Datadog::CI::Ext::Git::TAG_COMMIT_SHA => commit_sha_1,
          Datadog::CI::Ext::Git::TAG_REPOSITORY_URL => repo_url_1
        }
      end

      it "emits no discrepancy metrics" do
        subject.check_for_discrepancies

        expect(@metrics[:inc].select { |m| m.name == Datadog::CI::Ext::Telemetry::METRIC_GIT_COMMIT_SHA_DISCREPANCY }).to be_empty
      end

      it "emits match metric with matched: true" do
        subject.check_for_discrepancies

        match_metric = telemetry_metric(:inc, Datadog::CI::Ext::Telemetry::METRIC_GIT_COMMIT_SHA_MATCH)
        expect(match_metric).not_to be_nil
        expect(match_metric.value).to eq(1)
        expect(match_metric.tags).to eq({matched: "true"})
      end
    end

    context "when CI provider and local git commit SHAs differ" do
      let(:ci_provider_env_tags) do
        {Datadog::CI::Ext::Git::TAG_COMMIT_SHA => commit_sha_1}
      end
      let(:local_git_tags) do
        {Datadog::CI::Ext::Git::TAG_COMMIT_SHA => commit_sha_2}
      end

      it "emits commit discrepancy metric" do
        subject.check_for_discrepancies

        discrepancy_metric = telemetry_metric(:inc, Datadog::CI::Ext::Telemetry::METRIC_GIT_COMMIT_SHA_DISCREPANCY)
        expect(discrepancy_metric).not_to be_nil
        expect(discrepancy_metric.value).to eq(1)
        expect(discrepancy_metric.tags).to eq({
          type: "commit_discrepancy",
          expected_provider: "ci_provider",
          discrepant_provider: "git_client"
        })
      end

      it "emits match metric with matched: false" do
        subject.check_for_discrepancies

        match_metric = telemetry_metric(:inc, Datadog::CI::Ext::Telemetry::METRIC_GIT_COMMIT_SHA_MATCH)
        expect(match_metric).not_to be_nil
        expect(match_metric.tags).to eq({matched: "false"})
      end
    end

    context "when user provided and local git commit SHAs differ" do
      let(:user_provided_tags) do
        {Datadog::CI::Ext::Git::TAG_COMMIT_SHA => commit_sha_1}
      end
      let(:local_git_tags) do
        {Datadog::CI::Ext::Git::TAG_COMMIT_SHA => commit_sha_2}
      end

      it "emits commit discrepancy metric with user_supplied provider" do
        subject.check_for_discrepancies

        discrepancy_metric = telemetry_metric(:inc, Datadog::CI::Ext::Telemetry::METRIC_GIT_COMMIT_SHA_DISCREPANCY)
        expect(discrepancy_metric).not_to be_nil
        expect(discrepancy_metric.tags).to eq({
          type: "commit_discrepancy",
          expected_provider: "user_supplied",
          discrepant_provider: "git_client"
        })
      end
    end

    context "when user provided and CI provider commit SHAs differ" do
      let(:user_provided_tags) do
        {Datadog::CI::Ext::Git::TAG_COMMIT_SHA => commit_sha_1}
      end
      let(:ci_provider_env_tags) do
        {Datadog::CI::Ext::Git::TAG_COMMIT_SHA => commit_sha_2}
      end

      it "emits commit discrepancy metric comparing user and CI provider" do
        subject.check_for_discrepancies

        discrepancy_metric = telemetry_metric(:inc, Datadog::CI::Ext::Telemetry::METRIC_GIT_COMMIT_SHA_DISCREPANCY)
        expect(discrepancy_metric).not_to be_nil
        expect(discrepancy_metric.tags).to eq({
          type: "commit_discrepancy",
          expected_provider: "user_supplied",
          discrepant_provider: "ci_provider"
        })
      end
    end

    context "when CI provider and local git repository URLs differ" do
      let(:ci_provider_env_tags) do
        {Datadog::CI::Ext::Git::TAG_REPOSITORY_URL => repo_url_1}
      end
      let(:local_git_tags) do
        {Datadog::CI::Ext::Git::TAG_REPOSITORY_URL => repo_url_2}
      end

      it "emits repository discrepancy metric" do
        subject.check_for_discrepancies

        discrepancy_metric = telemetry_metric(:inc, Datadog::CI::Ext::Telemetry::METRIC_GIT_COMMIT_SHA_DISCREPANCY)
        expect(discrepancy_metric).not_to be_nil
        expect(discrepancy_metric.tags).to eq({
          type: "repository_discrepancy",
          expected_provider: "ci_provider",
          discrepant_provider: "git_client"
        })
      end
    end

    context "when user provided and local git repository URLs differ" do
      let(:user_provided_tags) do
        {Datadog::CI::Ext::Git::TAG_REPOSITORY_URL => repo_url_1}
      end
      let(:local_git_tags) do
        {Datadog::CI::Ext::Git::TAG_REPOSITORY_URL => repo_url_2}
      end

      it "emits repository discrepancy metric with user_supplied provider" do
        subject.check_for_discrepancies

        discrepancy_metric = telemetry_metric(:inc, Datadog::CI::Ext::Telemetry::METRIC_GIT_COMMIT_SHA_DISCREPANCY)
        expect(discrepancy_metric).not_to be_nil
        expect(discrepancy_metric.tags).to eq({
          type: "repository_discrepancy",
          expected_provider: "user_supplied",
          discrepant_provider: "git_client"
        })
      end
    end

    context "when user provided and CI provider repository URLs differ" do
      let(:user_provided_tags) do
        {Datadog::CI::Ext::Git::TAG_REPOSITORY_URL => repo_url_1}
      end
      let(:ci_provider_env_tags) do
        {Datadog::CI::Ext::Git::TAG_REPOSITORY_URL => repo_url_2}
      end

      it "emits repository discrepancy metric comparing user and CI provider" do
        subject.check_for_discrepancies

        discrepancy_metric = telemetry_metric(:inc, Datadog::CI::Ext::Telemetry::METRIC_GIT_COMMIT_SHA_DISCREPANCY)
        expect(discrepancy_metric).not_to be_nil
        expect(discrepancy_metric.tags).to eq({
          type: "repository_discrepancy",
          expected_provider: "user_supplied",
          discrepant_provider: "ci_provider"
        })
      end
    end

    context "when multiple discrepancies exist" do
      let(:ci_provider_env_tags) do
        {
          Datadog::CI::Ext::Git::TAG_COMMIT_SHA => commit_sha_1,
          Datadog::CI::Ext::Git::TAG_REPOSITORY_URL => repo_url_1
        }
      end
      let(:local_git_tags) do
        {
          Datadog::CI::Ext::Git::TAG_COMMIT_SHA => commit_sha_2,
          Datadog::CI::Ext::Git::TAG_REPOSITORY_URL => repo_url_2
        }
      end
      let(:user_provided_tags) do
        {
          Datadog::CI::Ext::Git::TAG_COMMIT_SHA => commit_sha_3,
          Datadog::CI::Ext::Git::TAG_REPOSITORY_URL => repo_url_3
        }
      end

      it "emits multiple discrepancy metrics" do
        subject.check_for_discrepancies

        discrepancy_metrics = @metrics[:inc].select { |m| m.name == Datadog::CI::Ext::Telemetry::METRIC_GIT_COMMIT_SHA_DISCREPANCY }
        expect(discrepancy_metrics.length).to eq(6) # All possible combinations should have discrepancies

        # Check that we have commit discrepancies
        commit_discrepancies = discrepancy_metrics.select { |m| m.tags[:type] == "commit_discrepancy" }
        expect(commit_discrepancies.length).to eq(3)

        # Check that we have repository discrepancies
        repo_discrepancies = discrepancy_metrics.select { |m| m.tags[:type] == "repository_discrepancy" }
        expect(repo_discrepancies.length).to eq(3)
      end

      it "emits match metric with matched: false" do
        subject.check_for_discrepancies

        match_metric = telemetry_metric(:inc, Datadog::CI::Ext::Telemetry::METRIC_GIT_COMMIT_SHA_MATCH)
        expect(match_metric).not_to be_nil
        expect(match_metric.tags).to eq({matched: "false"})
      end
    end

    context "edge cases" do
      context "when values are nil" do
        let(:ci_provider_env_tags) do
          {Datadog::CI::Ext::Git::TAG_COMMIT_SHA => nil}
        end
        let(:local_git_tags) do
          {Datadog::CI::Ext::Git::TAG_COMMIT_SHA => commit_sha_1}
        end

        it "does not emit discrepancy metrics for nil values" do
          subject.check_for_discrepancies

          discrepancy_metrics = @metrics[:inc].select { |m| m.name == Datadog::CI::Ext::Telemetry::METRIC_GIT_COMMIT_SHA_DISCREPANCY }
          expect(discrepancy_metrics).to be_empty
        end

        it "emits match metric with matched: true when no valid comparisons are made" do
          subject.check_for_discrepancies

          match_metric = telemetry_metric(:inc, Datadog::CI::Ext::Telemetry::METRIC_GIT_COMMIT_SHA_MATCH)
          expect(match_metric).not_to be_nil
          expect(match_metric.tags).to eq({matched: "true"})
        end
      end

      context "when values are empty strings" do
        let(:ci_provider_env_tags) do
          {Datadog::CI::Ext::Git::TAG_COMMIT_SHA => ""}
        end
        let(:local_git_tags) do
          {Datadog::CI::Ext::Git::TAG_COMMIT_SHA => commit_sha_1}
        end

        it "does not emit discrepancy metrics for empty string values (treated as nil)" do
          subject.check_for_discrepancies

          discrepancy_metrics = @metrics[:inc].select { |m| m.name == Datadog::CI::Ext::Telemetry::METRIC_GIT_COMMIT_SHA_DISCREPANCY }
          expect(discrepancy_metrics).to be_empty
        end
      end

      context "when tags are missing entirely" do
        let(:ci_provider_env_tags) { {} }
        let(:local_git_tags) { {} }
        let(:user_provided_tags) { {} }

        it "does not emit any discrepancy metrics" do
          subject.check_for_discrepancies

          discrepancy_metrics = @metrics[:inc].select { |m| m.name == Datadog::CI::Ext::Telemetry::METRIC_GIT_COMMIT_SHA_DISCREPANCY }
          expect(discrepancy_metrics).to be_empty
        end

        it "emits match metric with matched: true" do
          subject.check_for_discrepancies

          match_metric = telemetry_metric(:inc, Datadog::CI::Ext::Telemetry::METRIC_GIT_COMMIT_SHA_MATCH)
          expect(match_metric).not_to be_nil
          expect(match_metric.tags).to eq({matched: "true"})
        end
      end

      context "when only one side has values" do
        let(:ci_provider_env_tags) do
          {Datadog::CI::Ext::Git::TAG_COMMIT_SHA => commit_sha_1}
        end
        let(:local_git_tags) { {} }
        let(:user_provided_tags) { {} }

        it "does not emit discrepancy metrics when comparison values are missing" do
          subject.check_for_discrepancies

          discrepancy_metrics = @metrics[:inc].select { |m| m.name == Datadog::CI::Ext::Telemetry::METRIC_GIT_COMMIT_SHA_DISCREPANCY }
          expect(discrepancy_metrics).to be_empty
        end
      end

      context "when values are identical strings" do
        let(:same_sha) { commit_sha_1 }
        let(:ci_provider_env_tags) do
          {Datadog::CI::Ext::Git::TAG_COMMIT_SHA => same_sha}
        end
        let(:local_git_tags) do
          {Datadog::CI::Ext::Git::TAG_COMMIT_SHA => same_sha}
        end
        let(:user_provided_tags) do
          {Datadog::CI::Ext::Git::TAG_COMMIT_SHA => same_sha}
        end

        it "does not emit discrepancy metrics for identical values" do
          subject.check_for_discrepancies

          discrepancy_metrics = @metrics[:inc].select { |m| m.name == Datadog::CI::Ext::Telemetry::METRIC_GIT_COMMIT_SHA_DISCREPANCY }
          expect(discrepancy_metrics).to be_empty
        end

        it "emits match metric with matched: true" do
          subject.check_for_discrepancies

          match_metric = telemetry_metric(:inc, Datadog::CI::Ext::Telemetry::METRIC_GIT_COMMIT_SHA_MATCH)
          expect(match_metric).not_to be_nil
          expect(match_metric.tags).to eq({matched: "true"})
        end
      end

      context "when values have different case sensitivity" do
        let(:ci_provider_env_tags) do
          {Datadog::CI::Ext::Git::TAG_COMMIT_SHA => "ABC123456789012345678901234567890ABCDEF12"}
        end
        let(:local_git_tags) do
          {Datadog::CI::Ext::Git::TAG_COMMIT_SHA => "abc123456789012345678901234567890abcdef12"}
        end

        it "emits discrepancy metrics for case-different values" do
          subject.check_for_discrepancies

          discrepancy_metric = telemetry_metric(:inc, Datadog::CI::Ext::Telemetry::METRIC_GIT_COMMIT_SHA_DISCREPANCY)
          expect(discrepancy_metric).not_to be_nil
          expect(discrepancy_metric.tags).to eq({
            type: "commit_discrepancy",
            expected_provider: "ci_provider",
            discrepant_provider: "git_client"
          })
        end
      end
    end

    context "telemetry metric verification" do
      let(:ci_provider_env_tags) do
        {Datadog::CI::Ext::Git::TAG_COMMIT_SHA => commit_sha_1}
      end
      let(:local_git_tags) do
        {Datadog::CI::Ext::Git::TAG_COMMIT_SHA => commit_sha_2}
      end

      it "always emits exactly one match metric" do
        subject.check_for_discrepancies

        match_metrics = @metrics[:inc].select { |m| m.name == Datadog::CI::Ext::Telemetry::METRIC_GIT_COMMIT_SHA_MATCH }
        expect(match_metrics.length).to eq(1)
      end

      it "increments discrepancy metrics with value 1" do
        subject.check_for_discrepancies

        discrepancy_metrics = @metrics[:inc].select { |m| m.name == Datadog::CI::Ext::Telemetry::METRIC_GIT_COMMIT_SHA_DISCREPANCY }
        discrepancy_metrics.each do |metric|
          expect(metric.value).to eq(1)
        end
      end

      it "increments match metric with value 1" do
        subject.check_for_discrepancies

        match_metric = telemetry_metric(:inc, Datadog::CI::Ext::Telemetry::METRIC_GIT_COMMIT_SHA_MATCH)
        expect(match_metric.value).to eq(1)
      end
    end
  end
end
