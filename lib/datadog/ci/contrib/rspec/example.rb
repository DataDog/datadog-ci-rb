# frozen_string_literal: true

require_relative "../../ext/test"
require_relative "../../git/local_repository"
require_relative "../../source_code/method_inspect"
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
            # ============================================
            # Main entry points
            # ============================================

            def run(*args)
              return super unless datadog_configuration[:enabled]
              return super if ::RSpec.configuration.dry_run? && !datadog_configuration[:dry_run_enabled]

              test_suite_span = test_tracing_component.start_test_suite(datadog_test_suite_name) if ci_queue?

              # don't report test to RSpec::Core::Reporter until retries are done
              @skip_reporting = true

              # we keep track of the last test failure if we encounter any
              test_failure = nil

              test_retries_component.with_retries do
                test_tracing_component.trace_test(
                  datadog_test_name,
                  datadog_test_suite_name,
                  tags: build_test_tags,
                  service: datadog_configuration[:service_name]
                ) do |test_span|
                  prepare_test_span(test_span)

                  # before each run remove any previous exception
                  @exception = nil

                  result = super

                  # When test job is canceled and RSpec is quitting we don't want to report the last test
                  # before RSpec context unwinds. This test might have some unrelated errors that we don't want to
                  # see in Datadog.
                  return result if ::RSpec.world.wants_to_quit

                  test_failure = handle_test_result(test_span, test_failure)
                  update_formatter_metadata(test_span)
                  restore_failure_state(test_span, test_failure)
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

            # ============================================
            # Test identification
            # ============================================

            def datadog_test_id
              @datadog_test_id ||= Utils::TestRun.datadog_test_id(
                datadog_test_name,
                datadog_test_suite_name,
                datadog_test_parameters
              )
            end

            def datadog_fqn_test_id
              @datadog_fqn_test_id ||= Utils::TestRun.datadog_test_id(
                datadog_test_name,
                datadog_test_suite_name
              )
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

            def datadog_unskippable?
              !!metadata[CI::Ext::Test::ITR_UNSKIPPABLE_OPTION]
            end

            # ============================================
            # Source location
            # ============================================

            def datadog_test_suite_source_file_path
              Git::LocalRepository.relative_to_root(metadata[:rerun_file_path])
            end

            # Returns the relative source file path for this example.
            #
            # Some test frameworks (like rswag) dynamically generate examples inside gem code,
            # which causes metadata[:file_path] to point to the gem's internal file instead of
            # the actual spec file. In such cases, we traverse the example_group hierarchy
            # to find the correct source file.
            def datadog_source_file
              resolve_source_location unless defined?(@datadog_source_file)
              @datadog_source_file
            end

            # Returns the source line number for this example.
            # This corresponds to the same location as datadog_source_file.
            def datadog_source_start
              resolve_source_location unless defined?(@datadog_source_start)
              @datadog_source_start
            end

            # Returns true if the source location was resolved from a parent example_group
            # rather than the example's own metadata.
            def datadog_source_location_from_parent?
              resolve_source_location unless defined?(@datadog_source_location_from_parent)
              @datadog_source_location_from_parent
            end

            # ============================================
            # Context hierarchy
            # ============================================

            # Returns list of context IDs for this example, from outermost to innermost.
            # Used for merging context-level coverage into test coverage.
            def datadog_context_ids
              traverse_example_group_hierarchy unless defined?(@datadog_context_ids)
              @datadog_context_ids
            end

            private

            # ============================================
            # Run method helpers
            # ============================================

            def build_test_tags
              # @type var tags : Hash[String, String]
              tags = {
                CI::Ext::Test::TAG_FRAMEWORK => Ext::FRAMEWORK,
                CI::Ext::Test::TAG_FRAMEWORK_VERSION => datadog_integration.version.to_s,
                CI::Ext::Test::TAG_SOURCE_FILE => datadog_source_file,
                CI::Ext::Test::TAG_SOURCE_START => datadog_source_start.to_s,
                CI::Ext::Test::TAG_PARAMETERS => datadog_test_parameters
              }

              # Only set source_end if the example's source location wasn't resolved from a parent
              # example_group. When we fall back to parent's location (e.g., for rswag tests),
              # the @example_block is defined in a different file (the gem), so its end line
              # would be inconsistent with source_file and source_start.
              unless datadog_source_location_from_parent?
                end_line = SourceCode::MethodInspect.last_line(@example_block)
                tags[CI::Ext::Test::TAG_SOURCE_END] = end_line.to_s if end_line
              end

              tags
            end

            def prepare_test_span(test_span)
              # Set context IDs on the test span for TIA context coverage merging
              test_span&.context_ids = datadog_context_ids

              test_span&.itr_unskippable! if datadog_unskippable?

              metadata[:skip] = test_span&.datadog_skip_reason if test_span&.should_skip?
            end

            def handle_test_result(test_span, test_failure)
              case execution_result.status
              when :passed
                test_span&.passed!
              when :failed
                test_span&.failed!(exception: execution_result.exception)

                # if any of the retries passed or test is quarantined, we don't fail the test run
                @exception = nil if test_span&.should_ignore_failures?
                test_failure = @exception
              else
                # :pending or nil
                test_span&.skipped!(
                  reason: execution_result.pending_message,
                  exception: execution_result.pending_exception
                )
              end

              test_failure
            end

            def update_formatter_metadata(test_span)
              return unless datadog_configuration[:datadog_formatter_enabled]

              update_retry_metadata(test_span) if test_span&.is_retry?

              metadata[Ext::METADATA_DD_QUARANTINED] = true if test_span&.quarantined?
              metadata[Ext::METADATA_DD_DISABLED] = true if test_span&.disabled?
              metadata[Ext::METADATA_DD_SKIPPED_BY_ITR] = true if test_span&.skipped_by_test_impact_analysis?
            end

            def update_retry_metadata(test_span)
              metadata[Ext::METADATA_DD_RETRIES] ||= 0
              metadata[Ext::METADATA_DD_RETRY_RESULTS] ||= Hash.new(0)

              metadata[Ext::METADATA_DD_RETRIES] += 1
              metadata[Ext::METADATA_DD_RETRY_REASON] = test_span&.retry_reason
              metadata[Ext::METADATA_DD_RETRY_RESULTS][test_span&.status] += 1
            end

            def restore_failure_state(test_span, test_failure)
              # at this point if we have encountered any test failure in any of the previous retries
              # we restore the @exception internal state if we should not skip failures for this run
              if test_failure && !test_span&.should_ignore_failures?
                @exception = test_failure
              end
            end

            # ============================================
            # Source location resolution
            # ============================================

            # Resolves both source file and line number together to ensure consistency.
            # When the example's file_path points outside the project (e.g., to a gem),
            # we use the parent example_group's location instead.
            def resolve_source_location
              example_file_path = metadata[:file_path]
              example_relative_path = Git::LocalRepository.relative_to_root(example_file_path)

              # First try the example's own file_path
              if valid_source_file_path?(example_relative_path, example_file_path)
                set_source_location(example_relative_path, metadata[:line_number], from_parent: false)
                return
              end

              # Traverse example_group hierarchy to find a valid source file
              example_group = metadata[:example_group]
              while example_group
                group_file_path = example_group[:file_path]

                if group_file_path
                  group_relative_path = Git::LocalRepository.relative_to_root(group_file_path)

                  if valid_source_file_path?(group_relative_path, group_file_path)
                    set_source_location(group_relative_path, example_group[:line_number], from_parent: true)
                    return
                  end
                end

                example_group = example_group[:parent_example_group]
              end

              # Fallback to the original (possibly invalid) values
              set_source_location(example_relative_path, metadata[:line_number], from_parent: false)
            end

            def set_source_location(relative_path, line_number, from_parent:)
              @datadog_source_file = relative_path
              @datadog_source_start = line_number
              @datadog_source_location_from_parent = from_parent
            end

            def valid_source_file_path?(relative_path, original_path)
              return false if relative_path.nil? || relative_path.empty?

              if original_path && File.absolute_path?(original_path)
                root = Git::LocalRepository.root

                # The path should start with the project root
                return original_path.start_with?(root)
              end

              true
            end

            # ============================================
            # Hierarchy traversal
            # ============================================

            def datadog_top_level_example_group
              traverse_example_group_hierarchy unless defined?(@datadog_top_level_example_group)
              @datadog_top_level_example_group
            end

            # Traverses the example group hierarchy once, populating both
            # @datadog_context_ids and @top_level_example_group.
            def traverse_example_group_hierarchy
              context_ids = []
              example_group = metadata[:example_group]
              top_level = example_group

              # Walk up the example group hierarchy
              while example_group
                # Use scoped_id as the stable identifier, fallback to file:line
                context_id = example_group[:scoped_id] ||
                  "#{example_group[:file_path]}:#{example_group[:line_number]}"

                context_ids << context_id
                top_level = example_group

                example_group = example_group[:parent_example_group]
              end

              @datadog_context_ids = context_ids
              @datadog_top_level_example_group = top_level

              Datadog.logger.debug do
                "RSpec: Built context chain for the test: #{context_ids.inspect}"
              end
            end

            def datadog_test_suite_description
              @datadog_test_suite_description ||= datadog_top_level_example_group[:description]
            end

            # ============================================
            # Component accessors
            # ============================================

            def datadog_integration
              CI::Contrib::Instrumentation.fetch_integration(:rspec)
            end

            def datadog_configuration
              Datadog.configuration.ci[:rspec]
            end

            def test_tracing_component
              Datadog.send(:components).test_tracing
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
