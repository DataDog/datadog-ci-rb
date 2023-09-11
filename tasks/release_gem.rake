Rake::Task["build"].enhance(["build:pre_check"])

desc "Checks executed before gem is built"
task :"build:pre_check" do
  require "rspec"
  ret = RSpec::Core::Runner.run(["spec/datadog/ci/release_gem_spec.rb"])
  raise "Release tests failed! See error output above." if ret != 0
end
