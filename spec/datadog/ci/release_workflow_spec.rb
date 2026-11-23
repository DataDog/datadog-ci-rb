require "fileutils"
require "open3"
require "tmpdir"
require "yaml"

RSpec.describe "release workflow" do
  subject(:result) do
    Open3.capture3(
      {
        "PATH" => "#{directory}/bin:/usr/bin:/bin",
        "GITHUB_REF_NAME" => "v1.2.3",
        "GITHUB_OUTPUT" => "#{directory}/outputs",
        "GEM_FILE" => "pkg/datadog-ci-1.2.3.gem",
        "CERTIFICATE_IDENTITY" => identity
      },
      "/bin/bash", "-e", "-o", "pipefail", "-c", script,
      chdir: directory
    )
  end

  let(:directory) { Dir.mktmpdir("release-workflow-") }
  let(:failure) { nil }
  let(:built_version) { "1.2.3" }
  let(:identity) { "https://github.com/DataDog/datadog-ci-rb/.github/workflows/publish.yml@refs/tags/v1.2.3" }
  let(:steps) { YAML.load_file(".github/workflows/publish.yml").fetch("jobs").fetch("release").fetch("steps") }
  let(:script) do
    names = ["Build gem", "Sign and verify gem", "Publish gem with attestation"]
    steps.select { |step| names.include?(step["name"]) }.map { |step| step.fetch("run") }.join("\n")
  end

  before do
    FileUtils.mkdir_p("#{directory}/bin")
    File.write("#{directory}/bin/bundle", <<~SH)
      #!/bin/bash
      set -e
      case "$*" in
        "exec rake build")
          mkdir -p pkg
          printf 'gem contents' > pkg/datadog-ci-#{built_version}.gem
          ;;
        "exec sigstore-cli sign "*)
          test "#{failure}" != sign
          printf 'signed bundle' > "$4.sigstore.json"
          ;;
        "exec sigstore-cli verify "*)
          test "#{failure}" != verify
          test "$5" = --bundle
          test "$6" = "$4.sigstore.json"
          test "$7" = --certificate-identity
          test "$8" = '#{identity}'
          test "$9" = --certificate-oidc-issuer
          test "${10}" = https://token.actions.githubusercontent.com
          test -s "$6"
          ;;
        *) exit 1 ;;
      esac
    SH
    File.write("#{directory}/bin/gem", <<~SH)
      #!/bin/bash
      printf '%s\\n' "$@" > pushed
    SH
    FileUtils.chmod(0o755, ["#{directory}/bin/bundle", "#{directory}/bin/gem"])
  end

  after { FileUtils.remove_entry(directory) }

  it "publishes the built gem with its verified attestation" do
    expect(result.last).to be_success, result.first(2).join("\n")
    expect(File.read("#{directory}/pushed").lines.map(&:chomp)).to eq([
      "push", "--host", "https://rubygems.org", "--attestation",
      "pkg/datadog-ci-1.2.3.gem.sigstore.json", "pkg/datadog-ci-1.2.3.gem"
    ])
  end

  context "when signing fails" do
    let(:failure) { "sign" }

    it "does not publish the gem" do
      expect(result.last).not_to be_success
      expect(File).not_to exist("#{directory}/pushed")
    end
  end

  context "when verification fails" do
    let(:failure) { "verify" }

    it "does not publish the gem" do
      expect(result.last).not_to be_success
      expect(File).not_to exist("#{directory}/pushed")
    end
  end

  context "when the tag does not match the built version" do
    let(:built_version) { "1.2.2" }

    it "does not publish the gem" do
      expect(result.last).not_to be_success
      expect(File).not_to exist("#{directory}/pushed")
    end
  end
end
