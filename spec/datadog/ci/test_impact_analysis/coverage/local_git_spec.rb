# frozen_string_literal: true

require "tmpdir"
require_relative "../../../../../lib/datadog/ci/test_impact_analysis/coverage/local_git"

RSpec.describe Datadog::CI::TestImpactAnalysis::Coverage::LocalGit do
  around do |example|
    Dir.mktmpdir("local-tia-git") do |directory|
      @directory = directory
      example.run
    end
  end

  def git(*args)
    output, status = Open3.capture2e("git", "-C", @directory, "-c", "user.name=Test", "-c", "user.email=test@example.com", *args)
    raise output unless status.success?
    output.strip
  end

  def write(path, content = "original")
    File.write(File.join(@directory, path), content)
  end

  subject(:repository) { described_class.new(@directory) }

  before do
    git("init", "--quiet")
    %w[committed.rb staged.rb working.rb old.rb deleted.rb].each { |path| write(path) }
    git("add", ".")
    git("commit", "--quiet", "-m", "baseline")
  end

  it "includes committed, staged, working, untracked, renamed, and deleted paths" do
    baseline = repository.head
    write("committed.rb", "committed")
    git("add", "committed.rb")
    git("commit", "--quiet", "-m", "change")
    write("staged.rb", "staged")
    git("add", "staged.rb")
    write("working.rb", "working")
    git("mv", "old.rb", "new.rb")
    File.delete(File.join(@directory, "deleted.rb"))
    write("spaces and\nnewline.rb")
    expect(repository.changed_files(baseline)).to match_array(
      ["committed.rb", "staged.rb", "working.rb", "old.rb", "new.rb", "deleted.rb", "spaces and\nnewline.rb"]
    )
  end

  it "returns no paths for a clean checkout" do
    expect(repository.changed_files(repository.head)).to eq([])
  end

  it "rejects unavailable commits and option-like input" do
    expect { repository.changed_files("a" * 40) }.to raise_error(RuntimeError)
    expect { repository.changed_files("--help") }.to raise_error(ArgumentError)
  end
end
