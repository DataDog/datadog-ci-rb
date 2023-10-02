require "json"

RSpec.describe ::Datadog::CI::Ext::Environment do
  let(:logger) { instance_double(Datadog::Core::Logger) }
  before do
    allow(Datadog).to receive(:logger).and_return(logger)
    allow(logger).to receive(:debug)
    allow(logger).to receive(:error)
  end

  describe ".tags" do
    subject(:extracted_tags) do
      ClimateControl.modify(environment_variables) { described_class.tags(env) }
    end

    let(:env) { {} }
    let(:environment_variables) { {} }

    Dir.glob("#{FIXTURE_DIR}/ci/*.json").sort.each do |filename|
      # Parse each CI provider file
      File.open(filename) do |f|
        context "for fixture #{File.basename(filename)}" do
          # Create a context for each example inside the JSON fixture file
          JSON.parse(f.read).each_with_index do |(env, fixture_tags), i|
            context "##{i}" do
              # Modify HOME so that '~' expansion matches CI home directory.
              let(:environment_variables) { super().merge("HOME" => env["HOME"]) }
              let(:env) { env }

              context "with git information" do
                include_context "with git fixture", "gitdir_with_commit"

                it "matches CI tags, with git fallback information" do
                  is_expected
                    .to eq(
                      {
                        "ci.workspace_path" => "#{Dir.pwd}/spec/support/fixtures/git",
                        "git.branch" => "master",
                        "git.commit.author.date" => "2011-02-16T13:00:00+00:00",
                        "git.commit.author.email" => "bot@friendly.test",
                        "git.commit.author.name" => "Friendly bot",
                        "git.commit.committer.date" => "2023-10-02T13:52:56+00:00",
                        "git.commit.committer.email" => "andrey.marchenko@datadoghq.com",
                        "git.commit.committer.name" => "Andrey Marchenko",
                        "git.commit.message" => "First commit with ❤️",
                        "git.commit.sha" => "c7f893648f656339f62fb7b4d8a6ecdf7d063835",
                        "git.repository_url" => "https://datadoghq.com/git/test.git"
                      }.merge(fixture_tags)
                    )
                end
              end

              context "without git information" do
                include_context "without git installed"

                it "matches only CI tags" do
                  is_expected.to eq(fixture_tags)
                end
              end
            end
          end
        end
      end
    end

    context "inside a git directory" do
      context "with a newly created git repository" do
        include_context "with git fixture", "gitdir_empty"
        it "matches tags" do
          is_expected.to eq("ci.workspace_path" => "#{Dir.pwd}/spec/support/fixtures/git")
        end
      end

      context "with a git repository with a commit" do
        include_context "with git fixture", "gitdir_with_commit"
        it "matches tags" do
          is_expected.to eq(
            "ci.workspace_path" => "#{Dir.pwd}/spec/support/fixtures/git",
            "git.branch" => "master",
            "git.commit.author.date" => "2011-02-16T13:00:00+00:00",
            "git.commit.author.email" => "bot@friendly.test",
            "git.commit.author.name" => "Friendly bot",
            "git.commit.committer.date" => "2023-10-02T13:52:56+00:00",
            "git.commit.committer.email" => "andrey.marchenko@datadoghq.com",
            "git.commit.committer.name" => "Andrey Marchenko",
            "git.commit.message" => "First commit with ❤️",
            "git.commit.sha" => "c7f893648f656339f62fb7b4d8a6ecdf7d063835",
            "git.repository_url" => "https://datadoghq.com/git/test.git"
          )
        end
      end

      context "not inside a git repository" do
        let(:environment_variables) { {"GIT_DIR" => "./tmp/not-a-git-dir"} }

        it "does not fail" do
          is_expected.to eq({})
        end
      end

      context "without git installed nor CI information" do
        include_context "without git installed"

        it "does not fail" do
          is_expected.to eq({})

          expect(logger).to have_received(:debug).with(/No such file or directory - git/).at_least(1).time
        end
      end

      context "user provided metadata" do
        context "when required values are present" do
          include_context "with git fixture", "gitdir_with_commit"

          let(:env) do
            {
              "DD_GIT_REPOSITORY_URL" => "https://datadoghq.com/git/user-provided.git",
              "DD_GIT_COMMIT_SHA" => "9322CA1d57975b49b8c00b449d21b06660ce8b5c",
              "DD_GIT_BRANCH" => "my-branch",
              "DD_GIT_TAG" => "my-tag",
              "DD_GIT_COMMIT_MESSAGE" => "provided message",
              "DD_GIT_COMMIT_AUTHOR_NAME" => "user",
              "DD_GIT_COMMIT_AUTHOR_EMAIL" => "user@provided.com",
              "DD_GIT_COMMIT_AUTHOR_DATE" => "2021-06-18T18:35:10+00:00",
              "DD_GIT_COMMIT_COMMITTER_NAME" => "user committer",
              "DD_GIT_COMMIT_COMMITTER_EMAIL" => "user-committer@provided.com",
              "DD_GIT_COMMIT_COMMITTER_DATE" => "2021-06-19T18:35:10+00:00"
            }
          end

          it "returns user provided metadata" do
            is_expected.to eq(
              {
                "ci.workspace_path" => "#{Dir.pwd}/spec/support/fixtures/git",
                "git.branch" => env["DD_GIT_BRANCH"],
                "git.tag" => env["DD_GIT_TAG"],
                "git.commit.author.date" => env["DD_GIT_COMMIT_AUTHOR_DATE"],
                "git.commit.author.email" => env["DD_GIT_COMMIT_AUTHOR_EMAIL"],
                "git.commit.author.name" => env["DD_GIT_COMMIT_AUTHOR_NAME"],
                "git.commit.committer.date" => env["DD_GIT_COMMIT_COMMITTER_DATE"],
                "git.commit.committer.email" => env["DD_GIT_COMMIT_COMMITTER_EMAIL"],
                "git.commit.committer.name" => env["DD_GIT_COMMIT_COMMITTER_NAME"],
                "git.commit.message" => env["DD_GIT_COMMIT_MESSAGE"],
                "git.commit.sha" => env["DD_GIT_COMMIT_SHA"],
                "git.repository_url" => env["DD_GIT_REPOSITORY_URL"]
              }
            )
          end
        end

        context "with no git information extracted" do
          include_context "without git installed"

          context "when DD_GIT_REPOSITORY_URL is missing" do
            let(:env) do
              {
                "DD_GIT_COMMIT_SHA" => "9322ca1d57975b49b8c00b449d21b06660ce8b5c"
              }
            end

            it "logs an error" do
              is_expected.to eq(
                {
                  "git.commit.sha" => env["DD_GIT_COMMIT_SHA"]
                }
              )

              expect(logger).to have_received(:error).with(
                "DD_GIT_REPOSITORY_URL is not set or empty; no repo URL was automatically extracted"
              )
            end
          end

          context "when DD_GIT_COMMIT_SHA is missing" do
            let(:env) do
              {
                "DD_GIT_REPOSITORY_URL" => "https://datadoghq.com/git/user-provided.git"
              }
            end

            it "logs an error" do
              is_expected.to eq(
                {
                  "git.repository_url" => env["DD_GIT_REPOSITORY_URL"]
                }
              )

              expect(logger).to have_received(:error).with(
                "DD_GIT_COMMIT_SHA must be a full-length git SHA. No value was set and no SHA was automatically extracted."
              )
            end
          end

          context "when DD_GIT_COMMIT_SHA has invalid length" do
            let(:env) do
              {
                "DD_GIT_COMMIT_SHA" => "9322ca1d57975b49b8c00b449d21b06660ce8b5",
                "DD_GIT_REPOSITORY_URL" => "https://datadoghq.com/git/user-provided.git"
              }
            end

            it "logs an error" do
              is_expected.to eq(
                {
                  "git.commit.sha" => env["DD_GIT_COMMIT_SHA"],
                  "git.repository_url" => env["DD_GIT_REPOSITORY_URL"]
                }
              )

              expect(logger).to have_received(:error).with(
                "DD_GIT_COMMIT_SHA must be a full-length git SHA. Expected SHA length 40, was 39."
              )
            end
          end

          context "when DD_GIT_COMMIT_SHA is not a valid hex number" do
            let(:env) do
              {
                "DD_GIT_COMMIT_SHA" => "9322ca1d57975by9b8c00b449d21b06660ce8b5c",
                "DD_GIT_REPOSITORY_URL" => "https://datadoghq.com/git/user-provided.git"
              }
            end

            it "logs an error" do
              is_expected.to eq(
                {
                  "git.commit.sha" => env["DD_GIT_COMMIT_SHA"],
                  "git.repository_url" => env["DD_GIT_REPOSITORY_URL"]
                }
              )

              expect(logger).to have_received(:error).with(
                "DD_GIT_COMMIT_SHA must be a full-length git SHA. " \
                "Expected SHA to be a valid HEX number, got 9322ca1d57975by9b8c00b449d21b06660ce8b5c."
              )
            end
          end
        end
      end
    end
  end
end
