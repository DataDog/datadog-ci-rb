RSpec.describe "RSpec instrumentation with parallel_tests runner" do
  before do
    # Verify public manual API isn't used
    expect(Datadog::CI).to receive(:start_test_session).never
    expect(Datadog::CI).to receive(:start_test_module).never
    expect(Datadog::CI).to receive(:start_test_suite).never
    expect(Datadog::CI).to receive(:start_test).never
  end

  include_context "CI mode activated" do
    let(:integration_name) { :no_instrument }
  end

  before do
    require_relative "../../../../../lib/datadog/ci/auto_instrument"
    require "parallel_tests"

    # Create a temporary directory for test files
    FileUtils.mkdir_p("spec/datadog/ci/contrib/parallel_tests/suite_under_test")

    # Write spec_helper file
    File.write("spec/datadog/ci/contrib/parallel_tests/suite_under_test/spec_helper.rb", <<~RUBY)
      require "rspec"
    RUBY

    # Write some test files that include passing, failing, and skipped tests
    File.write("spec/datadog/ci/contrib/parallel_tests/suite_under_test/test_a_spec.rb", <<~RUBY)
      RSpec.describe "TestA" do
        it "passes" do
          expect(1 + 1).to eq(2)
        end
      end
    RUBY

    File.write("spec/datadog/ci/contrib/parallel_tests/suite_under_test/test_b_spec.rb", <<~RUBY)
      RSpec.describe "TestB" do
        it "fails" do
          expect(1 + 1).to eq(3)
        end
      end
    RUBY

    File.write("spec/datadog/ci/contrib/parallel_tests/suite_under_test/test_c_spec.rb", <<~RUBY)
      RSpec.describe "TestC" do
        it "is skipped", skip: true do
          # Test is skipped
        end
      end
    RUBY

    # Prevent Kernel.exit from affecting our test process
    allow(Kernel).to receive(:exit).and_return(true)
    allow_any_instance_of(ParallelTests::CLI).to receive(:exit).and_return(true)
  end

  after do
    # Clean up temporary test files
    FileUtils.rm_rf("spec/datadog/ci/contrib/parallel_tests/suite_under_test")
  end

  it "instruments tests run with parallel_tests" do
    with_new_rspec_environment do
      # Run the tests with parallel_tests (2 processes)
      # Use ParallelTests::CLI directly to start test session in this process
      ParallelTests::CLI.new.run(
        ["--type", "rspec"] +
          %w[-- --default-path spec/datadog/ci/contrib/parallel_tests/suite_under_test --out /dev/null -- spec/datadog/ci/contrib/parallel_tests/suite_under_test]
      )
    end

    # Test session should be created
    expect(test_session_span).not_to be_nil
    expect(test_module_span).not_to be_nil

    # The overall session should be marked as failed
    expect([test_session_span, test_module_span]).to all have_fail_status
  end
end
