require "time"

RSpec.describe "RSpec hooks" do
  include_context "CI mode activated" do
    let(:integration_name) { :rspec }
    let(:integration_options) { {service_name: "lspec"} }
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

  it "creates span for example" do
    spec = with_new_rspec_environment do
      RSpec.describe "some test" do
        it "foo" do
          # DO NOTHING
        end
      end.tap(&:run)
    end

    expect(first_test_span.type).to eq(Datadog::CI::Ext::AppTypes::TYPE_TEST)
    expect(first_test_span.service).to eq("lspec")

    expect(first_test_span.name).to eq("foo")
    expect(first_test_span.resource).to eq("foo")
    expect(first_test_span.get_tag(Datadog::CI::Ext::Test::TAG_NAME)).to eq("foo")

    expect(first_test_span.get_tag(Datadog::CI::Ext::Test::TAG_SUITE)).to eq("some test at #{spec.file_path}")
    expect(first_test_span.get_tag(Datadog::CI::Ext::Test::TAG_SPAN_KIND)).to eq(Datadog::CI::Ext::AppTypes::TYPE_TEST)
    expect(first_test_span.get_tag(Datadog::CI::Ext::Test::TAG_TYPE)).to eq(Datadog::CI::Ext::Test::TEST_TYPE)
    expect(first_test_span.get_tag(Datadog::CI::Ext::Test::TAG_FRAMEWORK)).to eq(Datadog::CI::Contrib::RSpec::Ext::FRAMEWORK)
    expect(first_test_span.get_tag(Datadog::CI::Ext::Test::TAG_FRAMEWORK_VERSION)).to eq(
      Datadog::CI::Contrib::RSpec::Integration.version.to_s
    )
    expect(first_test_span.get_tag(Datadog::CI::Ext::Test::TAG_STATUS)).to eq(Datadog::CI::Ext::Test::Status::PASS)

    expect(first_test_span.get_tag(Datadog::CI::Ext::Test::TAG_SOURCE_FILE)).to eq(
      "spec/datadog/ci/contrib/rspec/instrumentation_spec.rb"
    )
    expect(first_test_span.get_tag(Datadog::CI::Ext::Test::TAG_SOURCE_START)).to eq("26")
    expect(first_test_span.get_tag(Datadog::CI::Ext::Test::TAG_CODEOWNERS)).to eq(
      "[\"@DataDog/ruby-guild\", \"@DataDog/ci-app-libraries\"]"
    )
  end

  it "creates spans for several examples" do
    expect(Datadog::CI::Ext::Environment).to receive(:tags).never

    num_examples = 20
    with_new_rspec_environment do
      RSpec.describe "many tests" do
        num_examples.times do |n|
          it n do
            # DO NOTHING
          end
        end
      end.run
    end

    expect(test_spans).to have(num_examples).items
  end

  it "creates span for unnamed examples" do
    with_new_rspec_environment do
      RSpec.describe "some unnamed test" do
        it {}
      end.run
    end

    expect(first_test_span.get_tag(Datadog::CI::Ext::Test::TAG_NAME)).to match(/example at .+/)
  end

  it "creates span for deeply nested examples" do
    spec = with_new_rspec_environment do
      RSpec.describe "some nested test" do
        context "1" do
          context "2" do
            context "3" do
              context "4" do
                context "5" do
                  context "6" do
                    context "7" do
                      context "8" do
                        context "9" do
                          context "10" do
                            it "foo" do
                              # DO NOTHING
                            end
                          end
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end.tap(&:run)
    end

    expect(first_test_span.resource).to eq("1 2 3 4 5 6 7 8 9 10 foo")
    expect(first_test_span.get_tag(Datadog::CI::Ext::Test::TAG_NAME)).to eq("1 2 3 4 5 6 7 8 9 10 foo")
    expect(first_test_span.get_tag(Datadog::CI::Ext::Test::TAG_SUITE)).to eq("some nested test at #{spec.file_path}")
  end

  it "creates spans for example with instrumentation" do
    with_new_rspec_environment do
      RSpec.describe "some test" do
        it "foo" do
          Datadog::Tracing.trace("get_time") do
            Time.now
          end
        end
      end.tap(&:run)
    end

    expect(test_spans).to have(1).items
    expect(tracer_spans).to have(1).items

    tracer_spans.each do |span|
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::Distributed::TAG_ORIGIN))
        .to eq(Datadog::CI::Ext::Test::CONTEXT_ORIGIN)
    end
  end

  context "catches failures" do
    def expect_failure
      expect(first_test_span.get_tag(Datadog::CI::Ext::Test::TAG_STATUS)).to eq(Datadog::CI::Ext::Test::Status::FAIL)
      expect(first_test_span).to have_error
      expect(first_test_span).to have_error_type
      expect(first_test_span).to have_error_message
      expect(first_test_span).to have_error_stack
    end

    it "within let" do
      with_new_rspec_environment do
        RSpec.describe "some failed test with let" do
          let(:let_failure) { raise "failure" }

          it "foo" do
            let_failure
          end
        end.run
      end

      expect_failure
    end

    it "within around" do
      with_new_rspec_environment do
        RSpec.describe "some failed test with around" do
          around do |example|
            example.run
            raise "failure"
          end

          it "foo" do
            # DO NOTHING
          end
        end.run
      end

      expect_failure
    end

    it "within before" do
      with_new_rspec_environment do
        RSpec.describe "some failed test with before" do
          before do
            raise "failure"
          end

          it "foo" do
            # DO NOTHING
          end
        end.run
      end

      expect_failure
    end

    it "within after" do
      with_new_rspec_environment do
        RSpec.describe "some failed test with after" do
          after do
            raise "failure"
          end

          it "foo" do
            # DO NOTHING
          end
        end.run
      end

      expect_failure
    end
  end

  context "with git root changed" do
    before do
      expect(Datadog::CI::Utils::Git).to receive(:root).and_return("#{Dir.pwd}/spec")
    end

    it "provides source file path relative to git root" do
      with_new_rspec_environment do
        RSpec.describe "some test" do
          it "foo" do
            # DO NOTHING
          end
        end.tap(&:run)
      end

      expect(first_test_span.get_tag(Datadog::CI::Ext::Test::TAG_SOURCE_FILE)).to eq(
        "datadog/ci/contrib/rspec/instrumentation_spec.rb"
      )
    end
  end

  context "with rspec runner" do
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

            if with_shared_test
              require_relative "some_shared_examples"
              include_examples "Testing shared examples", 2
              include_examples "Testing shared examples", 1
            end
          end
        end

        options = ::RSpec::Core::ConfigurationOptions.new(%w[--pattern none])
        ::RSpec::Core::Runner.new(options).run(devnull, devnull)

        spec
      end
    end

    it "creates test session span" do
      rspec_session_run

      expect(test_session_span).not_to be_nil

      expect(test_session_span.type).to eq(Datadog::CI::Ext::AppTypes::TYPE_TEST_SESSION)
      expect(test_session_span.get_tag(Datadog::CI::Ext::Test::TAG_SPAN_KIND)).to eq(
        Datadog::CI::Ext::AppTypes::TYPE_TEST
      )
      expect(test_session_span.get_tag(Datadog::CI::Ext::Test::TAG_TYPE)).to eq(
        Datadog::CI::Ext::Test::TEST_TYPE
      )
      expect(test_session_span.get_tag(Datadog::CI::Ext::Test::TAG_FRAMEWORK)).to eq(
        Datadog::CI::Contrib::RSpec::Ext::FRAMEWORK
      )
      expect(test_session_span.get_tag(Datadog::CI::Ext::Test::TAG_FRAMEWORK_VERSION)).to eq(
        Datadog::CI::Contrib::RSpec::Integration.version.to_s
      )
      expect(test_session_span.get_tag(Datadog::CI::Ext::Test::TAG_STATUS)).to eq(
        Datadog::CI::Ext::Test::Status::PASS
      )
    end

    it "creates test module span" do
      rspec_session_run

      expect(test_module_span).not_to be_nil

      expect(test_module_span.type).to eq(Datadog::CI::Ext::AppTypes::TYPE_TEST_MODULE)
      expect(test_module_span.name).to eq(test_command)

      expect(test_module_span.get_tag(Datadog::CI::Ext::Test::TAG_SPAN_KIND)).to eq(
        Datadog::CI::Ext::AppTypes::TYPE_TEST
      )
      expect(test_module_span.get_tag(Datadog::CI::Ext::Test::TAG_TYPE)).to eq(
        Datadog::CI::Ext::Test::TEST_TYPE
      )
      expect(test_module_span.get_tag(Datadog::CI::Ext::Test::TAG_FRAMEWORK)).to eq(
        Datadog::CI::Contrib::RSpec::Ext::FRAMEWORK
      )
      expect(test_module_span.get_tag(Datadog::CI::Ext::Test::TAG_FRAMEWORK_VERSION)).to eq(
        Datadog::CI::Contrib::RSpec::Integration.version.to_s
      )
      expect(test_module_span.get_tag(Datadog::CI::Ext::Test::TAG_STATUS)).to eq(
        Datadog::CI::Ext::Test::Status::PASS
      )
    end

    it "creates test suite span" do
      spec = rspec_session_run

      expect(test_suite_span).not_to be_nil

      expect(test_suite_span.type).to eq(Datadog::CI::Ext::AppTypes::TYPE_TEST_SUITE)
      expect(test_suite_span.name).to eq("SomeTest at #{spec.file_path}")

      expect(test_module_span.get_tag(Datadog::CI::Ext::Test::TAG_SPAN_KIND)).to eq(
        Datadog::CI::Ext::AppTypes::TYPE_TEST
      )
      expect(test_module_span.get_tag(Datadog::CI::Ext::Test::TAG_TYPE)).to eq(
        Datadog::CI::Ext::Test::TEST_TYPE
      )
      expect(test_module_span.get_tag(Datadog::CI::Ext::Test::TAG_FRAMEWORK)).to eq(
        Datadog::CI::Contrib::RSpec::Ext::FRAMEWORK
      )
      expect(test_module_span.get_tag(Datadog::CI::Ext::Test::TAG_FRAMEWORK_VERSION)).to eq(
        Datadog::CI::Contrib::RSpec::Integration.version.to_s
      )
      expect(test_module_span.get_tag(Datadog::CI::Ext::Test::TAG_STATUS)).to eq(
        Datadog::CI::Ext::Test::Status::PASS
      )
    end

    it "connects test to the session, module, and suite" do
      rspec_session_run

      expect(first_test_span.get_tag(Datadog::CI::Ext::Test::TAG_TEST_SESSION_ID)).to eq(test_session_span.id.to_s)
      expect(first_test_span.get_tag(Datadog::CI::Ext::Test::TAG_TEST_MODULE_ID)).to eq(test_module_span.id.to_s)
      expect(first_test_span.get_tag(Datadog::CI::Ext::Test::TAG_TEST_SUITE_ID)).to eq(test_suite_span.id.to_s)
    end

    context "with failures" do
      it "creates test session span with failed state" do
        rspec_session_run(with_failed_test: true)

        expect(test_session_span).not_to be_nil
        expect(test_session_span.get_tag(Datadog::CI::Ext::Test::TAG_STATUS)).to eq(
          Datadog::CI::Ext::Test::Status::FAIL
        )
      end

      it "creates test module span with failed state" do
        rspec_session_run(with_failed_test: true)

        expect(test_module_span).not_to be_nil
        expect(test_module_span.get_tag(Datadog::CI::Ext::Test::TAG_STATUS)).to eq(
          Datadog::CI::Ext::Test::Status::FAIL
        )
      end

      it "creates test suite span with failed state" do
        rspec_session_run(with_failed_test: true)

        expect(test_suite_span).not_to be_nil
        expect(test_suite_span.get_tag(Datadog::CI::Ext::Test::TAG_STATUS)).to eq(
          Datadog::CI::Ext::Test::Status::FAIL
        )
      end
    end

    context "with shared examples" do
      let!(:spec) { rspec_session_run(with_shared_test: true) }

      it "creates correct test spans connects all tests to a single test suite" do
        shared_test_spans = test_spans.filter { |test_span| test_span.name == "nested shared examples adds 1 and 1" }
        expect(shared_test_spans).to have(2).items

        shared_test_spans.each_with_index do |shared_test_span, index|
          expect(shared_test_span.get_tag(Datadog::CI::Ext::Test::TAG_SUITE)).to eq("SomeTest at #{spec.file_path}")

          expect(shared_test_span.get_tag(Datadog::CI::Ext::Test::TAG_PARAMETERS)).to eq(
            "{\"arguments\":{},\"metadata\":{\"scoped_id\":\"1:1:#{2 + index}:1\"}}"
          )
        end

        test_spans.each do |test_span|
          expect(test_span.get_tag(Datadog::CI::Ext::Test::TAG_TEST_SUITE_ID)).to eq(test_suite_span.id.to_s)
        end
      end
    end
  end
end
