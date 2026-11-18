# frozen_string_literal: true

require "tmpdir"
require "open3"
require "json"
require "zlib"

RSpec.describe "RSpec local coverage selection" do
  let(:project) { File.expand_path("../../../../..", __dir__) }

  around do |example|
    Dir.mktmpdir("rspec-local-coverage") do |directory|
      @directory = directory
      example.run
    end
  end

  def write(path, content)
    absolute = File.join(@directory, path)
    FileUtils.mkdir_p(File.dirname(absolute))
    File.write(absolute, content)
  end

  def git(*arguments)
    output, status = Open3.capture2e("git", "-C", @directory, "-c", "user.name=Test", "-c", "user.email=test@example.com", *arguments)
    raise output unless status.success?
    output.strip
  end

  def run_specs
    report = File.join(@directory, "tmp", "results.json")
    output, status = Open3.capture2e(
      {"BUNDLE_GEMFILE" => File.join(project, "Gemfile"), "DD_CIVISIBILITY_ENABLED" => "true",
       "DD_CIVISIBILITY_TIA_LOCAL_COVERAGE_FILE" => "tmp/coverage.json.gz", "DD_CIVISIBILITY_ITR_ENABLED" => "true"},
      RbConfig.ruby, "-I", File.join(project, "lib"), "-r", "bundler/setup", Gem.bin_path("rspec-core", "rspec"),
      "--require", "./spec/spec_helper.rb", "--format", "json", "--out", report, "spec", chdir: @directory
    )
    expect(status.success?).to be(true), output
    JSON.parse(File.read(report)).fetch("examples").to_h { |example| [example.fetch("description"), example.fetch("status")] }
  end

  before do
    git("init", "--quiet")
    git("remote", "add", "origin", "git@github.com:example/local-tia.git")
    write(".gitignore", "/tmp/\n")
    FileUtils.mkdir_p(File.join(@directory, "tmp"))
    write("lib/cart.rb", "module Cart; def self.total; 42; end; end\n")
    write("lib/billing.rb", "module Billing; def self.total; 7; end; end\n")
    write("fixtures/rate.txt", "rate\n")
    write("spec/spec_helper.rb", <<~RUBY)
      require "datadog/ci"
      Datadog.configure do |c|
        c.ci.enabled = true
        c.ci.tia_static_dependencies_tracking_enabled = false
        c.ci.instrument :rspec
      end
    RUBY
    write("spec/cart_spec.rb", <<~RUBY)
      require_relative "../lib/cart"
      RSpec.describe "Cart" do
        before(:context) { @rate = File.read("fixtures/rate.txt") }
        it("reads cart") { expect(Cart.total).to eq(42) }
      end
    RUBY
    write("spec/billing_spec.rb", <<~RUBY)
      require_relative "../lib/billing"
      RSpec.describe "Billing" do
        it("reads billing") { expect(Billing.total).to eq(7) }
      end
    RUBY
    git("add", ".")
    git("commit", "--quiet", "-m", "baseline")
  end

  it "collects a snapshot, selects affected tests, and runs new tests without replacing the snapshot" do
    expect(run_specs).to eq("reads cart" => "passed", "reads billing" => "passed")
    path = File.join(@directory, "tmp", "coverage.json.gz")
    bytes = File.binread(path)
    document = JSON.parse(Zlib.gunzip(bytes))
    expect(document.keys).to match_array(%w[version scope base_commit tests])
    cart = document.fetch("tests").find { |test| test["name"] == "reads cart" }
    expect(cart.fetch("files")).to include("lib/cart.rb", "spec/cart_spec.rb", "fixtures/rate.txt")
    expect(cart.fetch("parameters").fetch("metadata")).to have_key("scoped_id")

    expect(run_specs.values).to all eq("pending")
    write("fixtures/rate.txt", "changed rate\n")
    expect(run_specs).to eq("reads cart" => "passed", "reads billing" => "pending")
    git("checkout", "--", "fixtures/rate.txt")
    write("lib/billing.rb", "module Billing; def self.total; 3 + 4; end; end\n")
    git("add", "lib/billing.rb")
    git("commit", "--quiet", "-m", "billing change")
    expect(run_specs).to eq("reads cart" => "pending", "reads billing" => "passed")

    write("spec/new_spec.rb", 'RSpec.describe("New") { it("new test") { expect(true).to be true } }')
    expect(run_specs).to eq("reads cart" => "pending", "reads billing" => "passed", "new test" => "passed")
    expect(File.binread(path)).to eq(bytes)
  end

  it "runs all tests when the stored map is corrupt" do
    write("tmp/coverage.json.gz", "invalid gzip")
    expect(run_specs.values).to all eq("passed")
    expect(File.read(File.join(@directory, "tmp", "coverage.json.gz"))).to eq("invalid gzip")
  end
end
