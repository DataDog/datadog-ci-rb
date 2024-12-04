# frozen_string_literal: true

require_relative "../../ext/test"
require_relative "../../git/local_repository"
require_relative "../../utils/test_run"
require_relative "../instrumentation"
require_relative "ext"

module Datadog
  module CI
    module Contrib
      module RSpec
        # Instrument RSpec::Core::Example
        module Example
          def self.included(base)
            base.prepend(InstanceMethods)
          end

          module InstanceMethods
            def run(*args)
              return super if ::RSpec.configuration.dry_run? && !datadog_configuration[:dry_run_enabled]
              return super unless datadog_configuration[:enabled]

              test_suite_span = test_visibility_component.start_test_suite(datadog_test_suite_name) if ci_queue?

              # don't report test to RSpec::Core::Reporter until retries are done
              @skip_reporting = true

              test_retries_component.with_retries do
                test_visibility_component.trace_test(
                  datadog_test_name,
                  datadog_test_suite_name,
                  tags: {
                    CI::Ext::Test::TAG_FRAMEWORK => Ext::FRAMEWORK,
                    CI::Ext::Test::TAG_FRAMEWORK_VERSION => datadog_integration.version.to_s,
                    CI::Ext::Test::TAG_SOURCE_FILE => Git::LocalRepository.relative_to_root(metadata[:file_path]),
                    CI::Ext::Test::TAG_SOURCE_START => metadata[:line_number].to_s,
                    CI::Ext::Test::TAG_PARAMETERS => datadog_test_parameters
                  },
                  service: datadog_configuration[:service_name]
                ) do |test_span|
                  test_span&.itr_unskippable! if datadog_unskippable?

                  metadata[:skip] = CI::Ext::Test::ITR_TEST_SKIP_REASON if test_span&.skipped_by_itr?

                  # before each run remove any previous exception
                  @exception = nil

                  result = super

                  # When test job is canceled and RSpec is quitting we don't want to report the last test
                  # before RSpec context unwinds. This test might have some unrelated errors that we don't want to
                  # see in Datadog.
                  return result if ::RSpec.world.wants_to_quit

                  case execution_result.status
                  when :passed
                    test_span&.passed!
                  when :failed
                    test_span&.failed!(exception: execution_result.exception)
                    # if any of the retries passed, we don't fail the test run
                    @exception = nil if test_span&.any_retry_passed?
                  else
                    # :pending or nil
                    test_span&.skipped!(
                      reason: execution_result.pending_message,
                      exception: execution_result.pending_exception
                    )
                  end
                end
              end

              # this is a special case for ci-queue, we need to finish the test suite span created for a single test
              test_suite_span&.finish

              # after retries are done, we can finally report the test to RSpec
              @skip_reporting = false
              finish(reporter)
            end

            def finish(reporter)
              # By default finish test but do not report it to RSpec::Core::Reporter
              # it is going to be reported once after retries are done.
              #
              # We need to do this because RSpec breaks when we try to report the same example multiple times with different
              # results.
              return super unless @skip_reporting

              super(::RSpec::Core::NullReporter)
            end

            def datadog_test_id
              @datadog_test_id ||= Utils::TestRun.datadog_test_id(
                datadog_test_name,
                datadog_test_suite_name,
                datadog_test_parameters
              )
            end

            def datadog_unskippable?
              !!metadata[CI::Ext::Test::ITR_UNSKIPPABLE_OPTION]
            end

            private

            def fetch_top_level_example_group
              example_group = metadata[:example_group]
              parent_example_group = example_group[:parent_example_group]

              return example_group unless parent_example_group

              res = parent_example_group
              while (parent = res[:parent_example_group])
                res = parent
              end
              res
            end

            def datadog_integration
              CI::Contrib::Instrumentation.fetch_integration(:rspec)
            end

            def datadog_configuration
              Datadog.configuration.ci[:rspec]
            end

            def datadog_test_suite_description
              @datadog_test_suite_description ||= fetch_top_level_example_group[:description]
            end

            def datadog_test_name
              return @datadog_test_name if defined?(@datadog_test_name)

              test_name = full_description.strip
              if metadata[:description].empty?
                # for unnamed it blocks this appends something like "example at ./spec/some_spec.rb:10"
                test_name << " #{description}"
              end

              # remove example group description from test name to avoid duplication
              test_name = test_name.sub(datadog_test_suite_description, "").strip

              @datadog_test_name = test_name
            end

            def datadog_test_suite_name
              return @datadog_test_suite_name if defined?(@datadog_test_suite_name)

              suite_name = "#{datadog_test_suite_description} at #{metadata[:example_group][:rerun_file_path]}"

              if ci_queue?
                suite_name = "#{suite_name} (ci-queue running example [#{datadog_test_name}])"
              end

              @datadog_test_suite_name = suite_name
            end

            def datadog_test_parameters
              return @datadog_test_parameters if defined?(@datadog_test_parameters)

              @datadog_test_parameters = Utils::TestRun.test_parameters(
                metadata: {"scoped_id" => metadata[:scoped_id]}
              )
            end

            def test_visibility_component
              Datadog.send(:components).test_visibility
            end

            def test_retries_component
              Datadog.send(:components).test_retries
            end

            def ci_queue?
              !!defined?(::RSpec::Queue::ExampleExtension) &&
                self.class.ancestors.include?(::RSpec::Queue::ExampleExtension)
            end
          end
        end
      end
    end
  end
end
