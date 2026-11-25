# frozen_string_literal: true

# Run with rspec by child_processes_spec.rb, in a covered child process: the child loads the
# bootstrap first, then datadog-ci by code through spec_helper.
require "stringio"

RSpec.describe "A test session in a child process that loads datadog-ci after the bootstrap" do
  include_context "CI mode activated" do
    let(:integration_name) { :rspec }
    let(:itr_enabled) { true }
    let(:code_coverage_enabled) { true }
    let(:line_coverage_enabled) { true }
  end

  it "runs its tests without code coverage" do
    with_new_rspec_environment do
      RSpec.describe "Nested" do
        it "passes" do
          expect(2 + 2).to eq(4)
        end
      end

      options = ::RSpec::Core::ConfigurationOptions.new(%w[--pattern none])
      ::RSpec::Core::Runner.new(options).run(StringIO.new, StringIO.new)
    end

    expect(first_test_span).to have_pass_status
    expect(find_coverage_for_test(first_test_span)).to be_nil
  end
end
