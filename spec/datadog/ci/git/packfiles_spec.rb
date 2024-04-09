# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/git/packfiles"

RSpec.describe ::Datadog::CI::Git::Packfiles do
  # skip for jruby for now - old git version DD docker image
  before { skip if PlatformHelpers.jruby? }

  let(:commits) { Datadog::CI::Git::LocalRepository.git_commits }
  let(:included_commits) { commits[0..1] }
  let(:excluded_commits) { commits[2..] }

  describe ".generate" do
    it "yields packfile" do
      expect do |b|
        described_class.generate(included_commits: included_commits, excluded_commits: excluded_commits, &b)
      end.to yield_with_args(/\/.+\h{8}-\h{40}\.pack$/)
    end

    context "empty packfiles folder" do
      before do
        expect(Datadog::CI::Git::LocalRepository).to receive(:git_generate_packfiles).with(
          included_commits: included_commits,
          excluded_commits: excluded_commits,
          path: String
        ) do
          "pref"
        end
      end

      it "does not yield anything" do
        expect do |b|
          described_class.generate(included_commits: included_commits, excluded_commits: excluded_commits, &b)
        end.not_to yield_control
      end
    end

    context "something goes wrong" do
      before do
        expect(Dir).to receive(:mktmpdir).and_raise("error")
      end

      it "does not yield anything" do
        expect do |b|
          described_class.generate(included_commits: included_commits, excluded_commits: excluded_commits, &b)
        end.not_to yield_control
      end
    end

    context "tmp folder fails" do
      let(:current_process_tmp_folder) { File.join(Dir.pwd, "tmp", "packfiles") }
      let(:prefix) { "pref" }

      before do
        expect(Datadog::CI::Git::LocalRepository).to receive(:git_generate_packfiles).with(
          included_commits: included_commits,
          excluded_commits: excluded_commits,
          path: String
        ).and_return(nil)

        expect(Datadog::CI::Git::LocalRepository).to receive(:git_generate_packfiles).with(
          included_commits: included_commits,
          excluded_commits: excluded_commits,
          path: current_process_tmp_folder
        ) do
          File.write(File.join(current_process_tmp_folder, "#{prefix}-sha.idx"), "hello world")
          File.write(File.join(current_process_tmp_folder, "other-sha.pack"), "hello world")
          File.write(File.join(current_process_tmp_folder, "#{prefix}-sha.pack"), "hello world")

          prefix
        end
      end

      it "creates temporary folder in the current directory" do
        expect do |b|
          described_class.generate(included_commits: included_commits, excluded_commits: excluded_commits, &b)
        end.to yield_with_args(/^#{current_process_tmp_folder}\/pref-sha.pack$/)

        expect(File.exist?(current_process_tmp_folder)).to be_falsey
      end
    end

    context "packfile generation fails" do
      before do
        allow(Datadog::CI::Git::LocalRepository).to receive(:git_generate_packfiles).and_return(nil)
      end

      it "does not yield anything" do
        expect do |b|
          described_class.generate(included_commits: included_commits, excluded_commits: excluded_commits, &b)
        end.not_to yield_control
      end
    end
  end
end
