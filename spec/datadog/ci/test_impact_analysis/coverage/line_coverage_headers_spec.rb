# frozen_string_literal: true

require_relative "../../../../../ext/datadog_ci_native/line_coverage_headers"

RSpec.describe Datadog::CI::NativeBuild::LineCoverageHeaders do
  # The header directories that datadog-ruby_core_source packages, by gem version.
  let(:headers_3_5_6) do
    %w[ruby-3.2.0-p0 ruby-3.3.0-p0 ruby-3.3.5-p100 ruby-3.4.0-p0 ruby-4.0.0-p0 ruby-4.0.6-p0 ruby-4.1.0-preview1]
  end
  let(:headers_3_5_0) { %w[ruby-3.3.5-p100 ruby-3.4.0-p0 ruby-4.0.0-preview2 ruby-4.0.0-p0] }
  let(:headers_3_4_3) { %w[ruby-3.3.5-p100 ruby-3.4.0-p0 ruby-4.0.0-preview3] }

  def choose(directory_names, ruby_version, patchlevel)
    release = patchlevel >= 0
    exact = release ? "ruby-#{ruby_version}-p#{patchlevel}" : "ruby-#{ruby_version}-preview1"
    described_class.choose(
      directory_names, ruby_version: ruby_version, release: release, exact_directory_name: exact
    )
  end

  describe ".choose" do
    it "takes the headers named for the running Ruby" do
      expect(choose(headers_3_5_6 + ["ruby-3.3.8-p144"], "3.3.8", 144)).to eq("ruby-3.3.8-p144")
    end

    it "otherwise takes the newest release headers of the same minor version, not newer than the running Ruby" do
      expect(choose(headers_3_5_6, "3.2.11", 268)).to eq("ruby-3.2.0-p0")
      expect(choose(headers_3_5_6, "3.3.8", 144)).to eq("ruby-3.3.5-p100")
      expect(choose(headers_3_5_6, "3.3.4", 94)).to eq("ruby-3.3.0-p0")
      expect(choose(headers_3_5_6, "3.4.13", 195)).to eq("ruby-3.4.0-p0")
      expect(choose(headers_3_5_6, "4.0.10", 0)).to eq("ruby-4.0.6-p0")
      expect(choose(headers_3_5_0, "4.0.10", 0)).to eq("ruby-4.0.0-p0")
    end

    it "takes no pre-release headers for a release Ruby" do
      expect(choose(headers_3_4_3, "4.0.10", 0)).to be_nil
      expect(choose(headers_3_5_6, "4.1.0", 0)).to be_nil
    end

    it "takes no headers of another minor version or of a newer release" do
      expect(choose(%w[ruby-3.3.5-p100], "3.4.13", 195)).to be_nil
      expect(choose(%w[ruby-3.4.1-p0], "3.4.0", 0)).to be_nil
    end

    it "takes only the headers named for a pre-release Ruby" do
      expect(choose(headers_3_5_6, "4.1.0", -1)).to eq("ruby-4.1.0-preview1")
      expect(choose(headers_3_5_6 - ["ruby-4.1.0-preview1"] + ["ruby-4.1.0-p0"], "4.1.0", -1)).to be_nil
    end
  end

  describe ".missing_reason" do
    it "names the gem version and the headers it has for the running Ruby's minor version" do
      reason = described_class.missing_reason(headers_3_4_3, gem_version: "3.4.3", ruby_version: "4.0.10", release: true)

      expect(reason).to eq(
        "datadog-ruby_core_source 3.4.3 has no headers of a Ruby 4.0 release up to 4.0.10 " \
        "(its 4.0 headers: ruby-4.0.0-preview3)"
      )
    end

    it "says when the gem has no headers at all for the minor version" do
      reason = described_class.missing_reason(headers_3_4_3, gem_version: "3.4.3", ruby_version: "4.1.0", release: true)

      expect(reason).to end_with("(its 4.1 headers: none)")
    end

    it "says when the running Ruby is not a release" do
      reason = described_class.missing_reason(headers_3_5_6, gem_version: "3.5.6", ruby_version: "4.1.0", release: false)

      expect(reason).to eq(
        "Ruby 4.1.0 is not a release, and datadog-ruby_core_source 3.5.6 has no headers named for it " \
        "(its 4.1 headers: ruby-4.1.0-preview1)"
      )
    end
  end
end
