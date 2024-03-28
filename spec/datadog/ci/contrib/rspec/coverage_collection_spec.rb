# frozen_string_literal: true

RSpec.describe "RSpec code coverage collection" do
  include_context "CI mode activated" do
    let(:integration_name) { :rspec }
    let(:integration_options) { {service_name: "lspec"} }
    let(:itr_enabled) { true }
    let(:code_coverage_enabled) { true }
  end

  # Yields to a block in a new RSpec global context. All RSpec
  # test configuration and execution should be wrapped in this method.
  def with_new_rspec_environment
    old_configuration = ::RSpec.configuration
    old_world = ::RSpec.world
    ::RSpec.configuration = ::RSpec::Core::Configuration.new
    ::RSpec.world = ::RSpec::Core::World.new

    yield
  ensure
    ::RSpec.configuration = old_configuration
    ::RSpec.world = old_world
  end

  def devnull
    File.new("/dev/null", "w")
  end

  def rspec_session_run(with_failed_test: false, with_shared_test: false)
    with_new_rspec_environment do
      spec = RSpec.describe "SomeTest" do
        context "nested" do
          it "foo" do
            # DO NOTHING
          end

          if with_failed_test
            it "fails" do
              expect(1).to eq(2)
            end
          end
        end
      end

      options = ::RSpec::Core::ConfigurationOptions.new(%w[--pattern none])
      ::RSpec::Core::Runner.new(options).run(devnull, devnull)

      spec
    end
  end

  it "collects code coverage" do
    rspec_session_run(with_failed_test: true)

    expect(test_session_span).not_to be_nil
    expect(test_session_span).to have_test_tag(:code_coverage_enabled, "true")
    expect(test_session_span).to have_test_tag(:itr_test_skipping_type, "test")
    expect(test_session_span).to have_test_tag(:itr_test_skipping_enabled, "false")

    expect(test_spans).to have(2).items

    expect(coverage_events).to have(2).items
  end
end
