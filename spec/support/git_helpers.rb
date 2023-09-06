FIXTURE_DIR = "#{File.dirname(__FILE__)}/fixtures/" # rubocop:disable all

shared_context "with git fixture" do |git_fixture|
  let(:environment_variables) do
    super().merge("GIT_DIR" => "#{FIXTURE_DIR}/git/#{git_fixture}", "GIT_WORK_TREE" => "#{FIXTURE_DIR}/git/")
  end
end

shared_context "without git installed" do
  before { allow(Open3).to receive(:capture2e).and_raise(Errno::ENOENT, "No such file or directory - git") }
end
