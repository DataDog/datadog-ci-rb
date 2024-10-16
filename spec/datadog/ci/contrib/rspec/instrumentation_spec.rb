require "time"

RSpec.describe "RSpec hooks" do
  before do
    # expect that public manual API isn't used
    expect(Datadog::CI).to receive(:start_test_session).never
    expect(Datadog::CI).to receive(:start_test_module).never
    expect(Datadog::CI).to receive(:start_test_suite).never
    expect(Datadog::CI).to receive(:start_test).never
  end

  def rspec_session_run(
    with_failed_test: false,
    with_shared_test: false,
    with_shared_context: false,
    with_flaky_test: false,
    with_canceled_test: false,
    with_flaky_test_that_fails_once: false,
    unskippable: {
      test: false,
      context: false,
      suite: false
    },
    dry_run: false
  )
    test_meta = unskippable[:test] ? {Datadog::CI::Ext::Test::ITR_UNSKIPPABLE_OPTION => true} : {}
    context_meta = unskippable[:context] ? {Datadog::CI::Ext::Test::ITR_UNSKIPPABLE_OPTION => true} : {}
    suite_meta = unskippable[:suite] ? {Datadog::CI::Ext::Test::ITR_UNSKIPPABLE_OPTION => true} : {}

    max_flaky_test_failures = 4
    flaky_test_failures = 0

    max_flaky_test_that_fails_once_passes = 10
    flaky_test_that_fails_once_passes = 0

    current_let_value = 0

    with_new_rspec_environment do
      spec = RSpec.describe "SomeTest", suite_meta do
        context "nested", context_meta do
          let(:let_value) { current_let_value += 1 }

          it "foo", test_meta do
            expect(1 + 1).to eq(2)
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

          if with_shared_context
            require_relative "some_shared_context"
            include_context "Shared context"
          end

          if with_flaky_test
            it "flaky" do
              Datadog::CI.active_test&.set_tag("let_value", let_value)
              if flaky_test_failures < max_flaky_test_failures
                flaky_test_failures += 1
                expect(1 + 1).to eq(3)
              else
                expect(1 + 1).to eq(2)
              end
            end
          end

          if with_flaky_test_that_fails_once
            it "flaky that fails once" do
              if flaky_test_that_fails_once_passes < max_flaky_test_that_fails_once_passes
                flaky_test_that_fails_once_passes += 1
                expect(1 + 1).to eq(2)
              else
                expect(1 + 1).to eq(3)
              end
            end
          end

          if with_canceled_test
            it "canceled during execution" do
              RSpec.world.wants_to_quit = true

              expect(1 + 1).to eq(34)
            end
          end
        end
      end

      options_array = %w[--pattern none]
      if dry_run
        options_array << "--dry-run"
      end
      options = ::RSpec::Core::ConfigurationOptions.new(options_array)
      ::RSpec::Core::Runner.new(options).run(devnull, devnull)

      spec
    end
  end

  context "running individual tests" do
    include_context "CI mode activated" do
      let(:integration_name) { :rspec }
      let(:integration_options) { {service_name: "lspec"} }
    end

    before do
      Datadog.send(:components).test_visibility.start_test_session
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

      expect(first_test_span).to have_test_tag(:name, "foo")
      expect(first_test_span).to have_test_tag(:suite, "some test at #{spec.file_path}")

      expect(first_test_span).to have_test_tag(:span_kind, "test")
      expect(first_test_span).to have_test_tag(:type, "test")

      expect(first_test_span).to have_test_tag(:framework, "rspec")
      expect(first_test_span).to have_test_tag(
        :framework_version,
        Datadog::CI::Contrib::RSpec::Integration.version.to_s
      )

      expect(first_test_span).to have_pass_status

      expect(first_test_span).to have_test_tag(
        :source_file,
        "spec/datadog/ci/contrib/rspec/instrumentation_spec.rb"
      )
      expect(first_test_span).to have_test_tag(:source_start, "121")
      expect(first_test_span).to have_test_tag(
        :codeowners,
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

      expect(first_test_span).to have_test_tag(:name, /example at .+/)
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
      expect(first_test_span).to have_test_tag(:name, "1 2 3 4 5 6 7 8 9 10 foo")
      expect(first_test_span).to have_test_tag(:suite, "some nested test at #{spec.file_path}")
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
      expect(custom_spans).to have(1).items
      expect(custom_spans).to all have_origin(Datadog::CI::Ext::Test::CONTEXT_ORIGIN)
    end

    context "catches failures" do
      def expect_failure
        expect(first_test_span).to have_fail_status
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

    context "supports skipped examples" do
      it "with skip: true" do
        with_new_rspec_environment do
          RSpec.describe "some skipped test" do
            it "foo", skip: true do
              expect(1 + 1).to eq(5)
            end
          end.run
        end

        expect(first_test_span).to have_test_tag(:name, "foo")

        expect(first_test_span).to have_skip_status
        expect(first_test_span).to have_test_tag(:skip_reason, "No reason given")
        expect(first_test_span).not_to have_error
      end

      it "with skip: reason" do
        with_new_rspec_environment do
          RSpec.describe "some skipped test" do
            it "foo", skip: "reason in it block" do
              expect(1 + 1).to eq(5)
            end
          end.run
        end

        expect(first_test_span).to have_test_tag(:name, "foo")

        expect(first_test_span).to have_skip_status
        expect(first_test_span).to have_test_tag(:skip_reason, "reason in it block")
        expect(first_test_span).not_to have_error
      end

      it "with skip instead of it" do
        with_new_rspec_environment do
          RSpec.describe "some skipped test" do
            skip "foo" do
              expect(1 + 1).to eq(5)
            end
          end.run
        end

        expect(first_test_span).to have_test_tag(:name, "foo")

        expect(first_test_span).to have_skip_status
        expect(first_test_span).to have_test_tag(:skip_reason, "No reason given")
        expect(first_test_span).not_to have_error
      end

      it "with xit" do
        with_new_rspec_environment do
          RSpec.describe "some skipped test" do
            xit "foo" do
              expect(1 + 1).to eq(5)
            end
          end.run
        end

        expect(first_test_span).to have_test_tag(:name, "foo")

        expect(first_test_span).to have_skip_status
        expect(first_test_span).to have_test_tag(:skip_reason, "Temporarily skipped with xit")
        expect(first_test_span).not_to have_error
      end

      it "with skip call" do
        with_new_rspec_environment do
          RSpec.describe "some skipped test" do
            it "foo" do
              skip
              expect(1 + 1).to eq(5)
            end
          end.run
        end

        expect(first_test_span).to have_test_tag(:name, "foo")

        expect(first_test_span).to have_skip_status
        expect(first_test_span).to have_test_tag(:skip_reason, "No reason given")
        expect(first_test_span).not_to have_error
      end

      it "with skip call and reason given" do
        with_new_rspec_environment do
          RSpec.describe "some skipped test" do
            it "foo" do
              skip("reason")
              expect(1 + 1).to eq(5)
            end
          end.run
        end

        expect(first_test_span).to have_test_tag(:name, "foo")

        expect(first_test_span).to have_skip_status
        expect(first_test_span).to have_test_tag(:skip_reason, "reason")
        expect(first_test_span).not_to have_error
      end

      it "with empty body" do
        with_new_rspec_environment do
          RSpec.describe "some skipped test" do
            it "foo"
          end.run
        end

        expect(first_test_span).to have_test_tag(:name, "foo")

        expect(first_test_span).to have_skip_status
        expect(first_test_span).to have_test_tag(:skip_reason, "Not yet implemented")
        expect(first_test_span).not_to have_error
      end

      it "with xcontext" do
        with_new_rspec_environment do
          RSpec.describe "some skipped test" do
            xcontext "foo" do
              it "bar" do
                expect(1 + 1).to eq(5)
              end
            end
          end.run
        end

        expect(first_test_span).to have_test_tag(:name, "foo bar")

        expect(first_test_span).to have_skip_status
        expect(first_test_span).to have_test_tag(:skip_reason, "Temporarily skipped with xcontext")
        expect(first_test_span).not_to have_error
      end

      it "with pending keyword and failure" do
        with_new_rspec_environment do
          RSpec.describe "some skipped test" do
            it "foo", pending: "did not fix the math yet" do
              expect(1 + 1).to eq(5)
            end
          end.run
        end

        expect(first_test_span).to have_test_tag(:name, "foo")

        expect(first_test_span).to have_skip_status
        expect(first_test_span).to have_test_tag(:skip_reason, "did not fix the math yet")
        expect(first_test_span).to have_error
      end

      it "with pending keyword and passing" do
        with_new_rspec_environment do
          RSpec.describe "some skipped test" do
            it "foo", pending: "did not fix the math yet" do
              expect(1 + 1).to eq(2)
            end
          end.run
        end

        expect(first_test_span).to have_test_tag(:name, "foo")

        expect(first_test_span).to have_fail_status
        expect(first_test_span).to have_error
        expect(first_test_span).to have_error_message("Expected example to fail since it is pending, but it passed.")
      end

      it "with pending method, reason and failure" do
        with_new_rspec_environment do
          RSpec.describe "some skipped test" do
            it "foo" do
              pending("did not fix the math yet")
              expect(1 + 1).to eq(5)
            end
          end.run
        end

        expect(first_test_span).to have_test_tag(:name, "foo")

        expect(first_test_span).to have_skip_status
        expect(first_test_span).to have_test_tag(:skip_reason, "did not fix the math yet")
        expect(first_test_span).to have_error
      end
    end

    context "with git root changed" do
      before do
        allow(Datadog::CI::Git::LocalRepository).to receive(:root).and_return("#{Dir.pwd}/spec")
      end

      it "provides source file path relative to git root" do
        with_new_rspec_environment do
          RSpec.describe "some test" do
            it "foo" do
              # DO NOTHING
            end
          end.tap(&:run)
        end

        expect(first_test_span).to have_test_tag(
          :source_file,
          "datadog/ci/contrib/rspec/instrumentation_spec.rb"
        )
      end
    end
  end

  context "with rspec runner" do
    include_context "CI mode activated" do
      let(:integration_name) { :rspec }
      let(:integration_options) { {service_name: "lspec"} }
    end

    it "creates test session span" do
      rspec_session_run

      expect(test_session_span).not_to be_nil

      expect(test_session_span.type).to eq("test_session_end")

      expect(test_session_span).to have_test_tag(:span_kind, "test")
      expect(test_session_span).to have_test_tag(:framework, "rspec")
      expect(test_session_span).to have_test_tag(
        :framework_version,
        Datadog::CI::Contrib::RSpec::Integration.version.to_s
      )

      expect(test_session_span).not_to have_test_tag(:code_coverage_enabled)

      # ITR
      expect(test_session_span).not_to have_test_tag(:itr_test_skipping_enabled)
      expect(test_session_span).not_to have_test_tag(:itr_test_skipping_type)
      expect(test_session_span).not_to have_test_tag(:itr_tests_skipped)
      expect(test_session_span).not_to have_test_tag(:itr_test_skipping_count)

      # Total code coverage
      expect(test_session_span).to have_test_tag(:code_coverage_lines_pct)

      expect(test_session_span).to have_pass_status
    end

    it "creates test module span" do
      rspec_session_run

      expect(test_module_span).not_to be_nil

      expect(test_module_span.type).to eq("test_module_end")
      expect(test_module_span.name).to eq("rspec")

      expect(test_module_span).to have_test_tag(:span_kind, "test")
      expect(test_module_span).to have_test_tag(:framework, "rspec")
      expect(test_module_span).to have_test_tag(
        :framework_version,
        Datadog::CI::Contrib::RSpec::Integration.version.to_s
      )
      expect(test_module_span).to have_pass_status
    end

    it "creates test suite span" do
      spec = rspec_session_run

      expect(first_test_suite_span).not_to be_nil

      expect(first_test_suite_span.type).to eq("test_suite_end")
      expect(first_test_suite_span.name).to eq("SomeTest at #{spec.file_path}")

      expect(first_test_suite_span).to have_test_tag(:span_kind, "test")
      expect(first_test_suite_span).to have_test_tag(:framework, "rspec")
      expect(first_test_suite_span).to have_test_tag(
        :framework_version,
        Datadog::CI::Contrib::RSpec::Integration.version.to_s
      )

      expect(first_test_suite_span).to have_test_tag(
        :source_file,
        "spec/datadog/ci/contrib/rspec/instrumentation_spec.rb"
      )
      expect(first_test_suite_span).to have_test_tag(:source_start, "39")
      expect(first_test_suite_span).to have_test_tag(
        :codeowners,
        "[\"@DataDog/ruby-guild\", \"@DataDog/ci-app-libraries\"]"
      )

      expect(first_test_suite_span).to have_pass_status
    end

    it "connects test to the session, module, and suite" do
      rspec_session_run

      expect(first_test_span).to have_test_tag(:test_session_id, test_session_span.id.to_s)
      expect(first_test_span).to have_test_tag(:test_module_id, test_module_span.id.to_s)
      expect(first_test_span).to have_test_tag(:test_suite_id, first_test_suite_span.id.to_s)
    end

    context "with failures" do
      it "creates test session span with failed state" do
        rspec_session_run(with_failed_test: true)

        expect(test_session_span).to have_fail_status
      end

      it "creates test module span with failed state" do
        rspec_session_run(with_failed_test: true)

        expect(test_module_span).to have_fail_status
      end

      it "creates test suite span with failed state" do
        rspec_session_run(with_failed_test: true)

        expect(first_test_suite_span).to have_fail_status
      end
    end

    context "with shared examples" do
      let!(:spec) { rspec_session_run(with_shared_test: true) }

      it "creates correct test spans connects all tests to a single test suite" do
        shared_test_spans = test_spans.filter { |test_span| test_span.name == "nested shared examples adds 1 and 1" }
        expect(shared_test_spans).to have(2).items

        shared_test_spans.each_with_index do |shared_test_span, index|
          expect(shared_test_span).to have_test_tag(:suite, "SomeTest at #{spec.file_path}")

          expect(shared_test_span).to have_test_tag(
            :parameters,
            "{\"arguments\":{},\"metadata\":{\"scoped_id\":\"1:1:#{2 + index}:1\"}}"
          )
        end

        expect(test_spans).to all have_test_tag(:test_suite_id, first_test_suite_span.id.to_s)
      end
    end

    context "with skipped test suite" do
      def rspec_skipped_session_run
        with_new_rspec_environment do
          RSpec.describe "SomeTest" do
            it "foo" do
              # DO NOTHING
            end
          end

          spec = RSpec.describe "SkippedTest" do
            context "nested" do
              it "skipped foo", skip: true do
                # DO NOTHING
              end

              it "pending fails" do
                pending("did not fix the math yet")
                expect(1).to eq(2)
              end
            end
          end

          options = ::RSpec::Core::ConfigurationOptions.new(%w[--pattern none])
          ::RSpec::Core::Runner.new(options).run(devnull, devnull)

          spec
        end
      end

      before do
        rspec_skipped_session_run
      end

      it "marks test session as passed" do
        expect(test_session_span).to have_pass_status
      end

      it "marks test suite as skipped" do
        skipped_suite = test_suite_spans.find do |suite_span|
          suite_span.get_tag(Datadog::CI::Ext::Test::TAG_SUITE).include?("SkippedTest")
        end

        expect(skipped_suite).to have_skip_status
      end
    end
  end

  context "with code coverage collected" do
    before { skip if PlatformHelpers.jruby? }

    before do
      allow(Datadog::CI::Git::LocalRepository).to receive(:root).and_return(__dir__)
    end

    include_context "CI mode activated" do
      let(:integration_name) { :rspec }
      let(:integration_options) { {service_name: "lspec"} }

      let(:itr_enabled) { true }
      let(:code_coverage_enabled) { true }
    end

    it "collects code coverage" do
      rspec_session_run(with_failed_test: true, with_shared_context: true)

      expect(test_session_span).not_to be_nil
      expect(test_session_span).to have_test_tag(:code_coverage_enabled, "true")
      expect(test_session_span).to have_test_tag(:itr_test_skipping_type, "test")
      expect(test_session_span).to have_test_tag(:itr_test_skipping_enabled, "false")

      expect(test_spans).to have(3).items

      expect(coverage_events).to have(3).items
      expect_coverage_events_belong_to_session(test_session_span)
      expect_coverage_events_belong_to_suite(first_test_suite_span)
      expect_coverage_events_belong_to_tests(test_spans)
      expect_non_empty_coverages

      # collects coverage from shared context files
      shared_context_test = test_spans.find { |span| span.name == "nested is 42" }
      shared_context_coverage = find_coverage_for_test(shared_context_test)

      expect(shared_context_coverage.coverage).to eq({
        File.join(__dir__, "some_shared_context.rb") => true
      })
    end
  end

  context "when skipping tests" do
    include_context "CI mode activated" do
      let(:integration_name) { :rspec }
      let(:integration_options) { {service_name: "lspec"} }

      let(:itr_enabled) { true }
      let(:tests_skipping_enabled) { true }
    end

    context "skipped a single test" do
      let(:itr_skippable_tests) do
        Set.new([
          'SomeTest at ./spec/datadog/ci/contrib/rspec/instrumentation_spec.rb.nested foo.{"arguments":{},"metadata":{"scoped_id":"1:1:1"}}'
        ])
      end

      it "skips test" do
        rspec_session_run(with_failed_test: true)

        expect(test_spans).to have(2).items
        expect(test_spans).to have_tag_values_no_order(:status, ["skip", "fail"])

        itr_skipped_test = test_spans.find { |span| span.name == "nested foo" }
        expect(itr_skipped_test).to have_test_tag(:itr_skipped_by_itr, "true")
      end

      it "sends test session level tags" do
        rspec_session_run(with_failed_test: true)

        expect(test_session_span).to have_test_tag(:itr_test_skipping_enabled, "true")
        expect(test_session_span).to have_test_tag(:itr_test_skipping_type, "test")
        expect(test_session_span).to have_test_tag(:itr_tests_skipped, "true")
        expect(test_session_span).to have_test_tag(:itr_test_skipping_count, 1)
      end
    end

    context "skipped all tests" do
      let(:itr_skippable_tests) do
        Set.new([
          'SomeTest at ./spec/datadog/ci/contrib/rspec/instrumentation_spec.rb.nested foo.{"arguments":{},"metadata":{"scoped_id":"1:1:1"}}',
          'SomeTest at ./spec/datadog/ci/contrib/rspec/instrumentation_spec.rb.nested fails.{"arguments":{},"metadata":{"scoped_id":"1:1:2"}}'
        ])
      end

      it "skips tests and suite" do
        rspec_session_run(with_failed_test: true)

        expect(test_spans).to have(2).items
        expect(test_spans).to all have_skip_status
        expect(test_spans).to all have_test_tag(:itr_skipped_by_itr, "true")
        expect(first_test_suite_span).to have_skip_status
      end

      it "sends test session level tags" do
        rspec_session_run(with_failed_test: true)

        expect(test_session_span).to have_test_tag(:itr_tests_skipped, "true")
        expect(test_session_span).to have_test_tag(:itr_test_skipping_count, 2)
      end

      context "but some tests are unskippable" do
        context "when a test is unskippable" do
          it "runs the test and adds forced run tag" do
            rspec_session_run(with_failed_test: true, unskippable: {test: true})

            expect(test_spans).to have(2).items
            expect(test_spans).to have_tag_values_no_order(:status, ["skip", "pass"])

            itr_unskippable_test = test_spans.find { |span| span.name == "nested foo" }
            expect(itr_unskippable_test).not_to have_test_tag(:itr_skipped_by_itr)
            expect(itr_unskippable_test).to have_test_tag(:itr_forced_run, "true")

            itr_skipped_test = test_spans.find { |span| span.name == "nested fails" }
            expect(itr_skipped_test).to have_test_tag(:itr_skipped_by_itr, "true")

            expect(test_session_span).to have_test_tag(:itr_tests_skipped, "true")
            expect(test_session_span).to have_test_tag(:itr_test_skipping_count, 1)
          end
        end

        context "when a context is unskippable" do
          it "runs all tests in context and adds forced run tag" do
            rspec_session_run(with_failed_test: true, unskippable: {context: true})

            expect(test_spans).to have(2).items
            expect(test_spans).to have_tag_values_no_order(:status, ["fail", "pass"])
            expect(test_spans).to all have_test_tag(:itr_forced_run, "true")

            expect(test_session_span).to have_test_tag(:itr_tests_skipped, "false")
            expect(test_session_span).to have_test_tag(:itr_test_skipping_count, 0)
          end
        end

        context "when a suite is unskippable" do
          it "runs all tests in context and adds forced run tag" do
            rspec_session_run(with_failed_test: true, unskippable: {suite: true})

            expect(test_spans).to have(2).items
            expect(test_spans).to have_tag_values_no_order(:status, ["fail", "pass"])
            expect(test_spans).to all have_test_tag(:itr_forced_run, "true")

            expect(test_session_span).to have_test_tag(:itr_tests_skipped, "false")
            expect(test_session_span).to have_test_tag(:itr_test_skipping_count, 0)
          end
        end
      end
    end
  end

  context "with dry run" do
    context "normal instrumentation" do
      include_context "CI mode activated" do
        let(:integration_name) { :rspec }
        let(:integration_options) { {service_name: "lspec"} }
      end

      it "does not instrument test session" do
        rspec_session_run(dry_run: true)

        expect(test_session_span).to be_nil
        expect(test_spans).to be_empty
      end
    end

    context "when dry run is enabled for rspec" do
      include_context "CI mode activated" do
        let(:integration_name) { :rspec }
        let(:integration_options) { {service_name: "lspec", dry_run_enabled: true} }
      end

      it "instruments test session" do
        rspec_session_run(dry_run: true)

        expect(test_session_span).not_to be_nil
        expect(test_spans).not_to be_empty
      end
    end
  end

  context "session with flaky spec and failed test retries enabled" do
    include_context "CI mode activated" do
      let(:integration_name) { :rspec }
      let(:integration_options) { {service_name: "lspec"} }

      let(:flaky_test_retries_enabled) { true }
    end

    it "retries test until it passes" do
      rspec_session_run(with_flaky_test: true)

      # 1 initial run of flaky test + 4 retries until pass + 1 passing test = 6 spans
      expect(test_spans).to have(6).items

      failed_spans, passed_spans = test_spans.partition { |span| span.get_tag("test.status") == "fail" }
      expect(failed_spans).to have(4).items
      expect(passed_spans).to have(2).items

      test_spans_by_test_name = test_spans.group_by { |span| span.get_tag("test.name") }
      expect(test_spans_by_test_name["nested flaky"]).to have(5).items

      # check that let values are cleared between retries
      let_values = test_spans_by_test_name["nested flaky"].map { |span| span.get_tag("let_value") }
      expect(let_values).to eq([1, 2, 3, 4, 5])

      # count how many spans were marked as retries
      retries_count = test_spans.count { |span| span.get_tag("test.is_retry") == "true" }
      expect(retries_count).to eq(4)

      expect(test_spans_by_test_name["nested foo"]).to have(1).item

      expect(test_suite_spans).to have(1).item
      expect(test_suite_spans.first).to have_pass_status

      expect(test_session_span).to have_pass_status
    end
  end

  context "session with flaky spec and failed test retries enabled with insufficient retries limit" do
    include_context "CI mode activated" do
      let(:integration_name) { :rspec }
      let(:integration_options) { {service_name: "lspec"} }

      let(:flaky_test_retries_enabled) { true }
      let(:retry_failed_tests_max_attempts) { 3 }
    end

    it "retries test until it passes" do
      rspec_session_run(with_flaky_test: true)

      # 1 initial run of flaky test + 3 unsuccessful retries + 1 passing test = 5 spans
      expect(test_spans).to have(5).items

      failed_spans, passed_spans = test_spans.partition { |span| span.get_tag("test.status") == "fail" }
      expect(failed_spans).to have(4).items
      expect(passed_spans).to have(1).items

      test_spans_by_test_name = test_spans.group_by { |span| span.get_tag("test.name") }
      expect(test_spans_by_test_name["nested flaky"]).to have(4).items

      # count how many spans were marked as retries
      retries_count = test_spans.count { |span| span.get_tag("test.is_retry") == "true" }
      expect(retries_count).to eq(3)

      expect(test_spans_by_test_name["nested foo"]).to have(1).item

      expect(test_suite_spans).to have(1).item
      expect(test_suite_spans.first).to have_fail_status

      expect(test_session_span).to have_fail_status
    end
  end

  context "session with flaky and failed specs and failed test retries enabled with low overall retries limit" do
    include_context "CI mode activated" do
      let(:integration_name) { :rspec }
      let(:integration_options) { {service_name: "lspec"} }

      let(:flaky_test_retries_enabled) { true }
      let(:retry_failed_tests_total_limit) { 1 }
    end

    it "retries failed test with no success and bails out of retrying flaky test" do
      rspec_session_run(with_flaky_test: true, with_failed_test: true)

      # 1 passing test + 1 failed test + 5 unsuccessful retries + 1 failed run of flaky test without retries = 8 spans
      expect(test_spans).to have(8).items

      failed_spans, passed_spans = test_spans.partition { |span| span.get_tag("test.status") == "fail" }
      expect(failed_spans).to have(7).items
      expect(passed_spans).to have(1).items

      test_spans_by_test_name = test_spans.group_by { |span| span.get_tag("test.name") }

      # it bailed out of retrying flaky test because global failed tests limit was exhausted already
      expect(test_spans_by_test_name["nested flaky"]).to have(1).item

      # count how many spans were marked as retries
      retries_count = test_spans.count { |span| span.get_tag("test.is_retry") == "true" }
      expect(retries_count).to eq(5)

      # it retried failing test 5 times
      expect(test_spans_by_test_name["nested fails"]).to have(6).items

      expect(test_suite_spans).to have(1).item
      expect(test_suite_spans.first).to have_fail_status

      expect(test_session_span).to have_fail_status
    end
  end

  context "session that is canceled during the test execution" do
    include_context "CI mode activated" do
      let(:integration_name) { :rspec }
      let(:integration_options) { {service_name: "lspec"} }
    end

    it "does not report the test that failed when RSpec was quitting" do
      rspec_session_run(with_canceled_test: true)

      expect(test_spans).to have(2).items
      test_spans.each do |test_span|
        expect(test_span).not_to have_test_tag(:status, "fail")
        expect(test_span.status).to eq(0)
      end
    end
  end

  context "session with early flake detection enabled" do
    include_context "CI mode activated" do
      let(:integration_name) { :rspec }

      let(:early_flake_detection_enabled) { true }
      let(:unique_tests_set) { Set.new(["SomeTest at ./spec/datadog/ci/contrib/rspec/instrumentation_spec.rb.nested fails."]) }
    end

    it "retries the new test 10 times" do
      rspec_session_run(with_failed_test: true)

      # 1 passing test + 10 new test retries + 1 failed test run = 12 spans
      expect(test_spans).to have(12).items

      failed_spans, passed_spans = test_spans.partition { |span| span.get_tag("test.status") == "fail" }
      expect(failed_spans).to have(1).items
      expect(passed_spans).to have(11).items

      test_spans_by_test_name = test_spans.group_by { |span| span.get_tag("test.name") }

      # it retried the new test 10 times
      expect(test_spans_by_test_name["nested foo"]).to have(11).item

      # count how many tests were marked as retries
      retries_count = test_spans.count { |span| span.get_tag("test.is_retry") == "true" }
      expect(retries_count).to eq(10)

      # count how many tests were marked as new
      new_tests_count = test_spans.count { |span| span.get_tag("test.is_new") == "true" }
      expect(new_tests_count).to eq(11)

      expect(test_suite_spans).to have(1).item
      expect(test_suite_spans.first).to have_fail_status

      expect(test_session_span).to have_fail_status
      expect(test_session_span).to have_test_tag(:early_flake_enabled, "true")
    end

    context "when test is slower than 5 seconds" do
      before do
        allow_any_instance_of(Datadog::Tracing::SpanOperation).to receive(:duration).and_return(6.0)
      end

      it "retries the new test 5 times" do
        rspec_session_run(with_failed_test: true)

        # 1 passing test + 5 new test retries + 1 failed test run = 7 spans
        expect(test_spans).to have(7).items

        test_spans_by_test_name = test_spans.group_by { |span| span.get_tag("test.name") }
        # it retried the new test 5 times
        expect(test_spans_by_test_name["nested foo"]).to have(6).item

        # count how many spans were marked as retries
        retries_count = test_spans.count { |span| span.get_tag("test.is_retry") == "true" }
        expect(retries_count).to eq(5)

        # count how many tests were marked as new
        new_tests_count = test_spans.count { |span| span.get_tag("test.is_new") == "true" }
        expect(new_tests_count).to eq(6)

        expect(test_suite_spans).to have(1).item
        expect(test_session_span).to have_fail_status
        expect(test_session_span).to have_test_tag(:early_flake_enabled, "true")
      end
    end

    context "when test is slower than 10 minutes" do
      before do
        allow_any_instance_of(Datadog::Tracing::SpanOperation).to receive(:duration).and_return(601.0)
      end

      it "doesn't retry the new test" do
        rspec_session_run(with_failed_test: true)

        # 1 passing test + 1 failed test run = 2 spans
        expect(test_spans).to have(2).items

        test_spans_by_test_name = test_spans.group_by { |span| span.get_tag("test.name") }
        # it retried the new test 0 times
        expect(test_spans_by_test_name["nested foo"]).to have(1).item

        # count how many spans were marked as retries
        retries_count = test_spans.count { |span| span.get_tag("test.is_retry") == "true" }
        expect(retries_count).to eq(0)

        # count how many tests were marked as new
        new_tests_count = test_spans.count { |span| span.get_tag("test.is_new") == "true" }
        expect(new_tests_count).to eq(1)

        expect(test_suite_spans).to have(1).item
        expect(test_session_span).to have_fail_status
        expect(test_session_span).to have_test_tag(:early_flake_enabled, "true")
      end
    end
  end

  context "session with early flake detection enabled but unique tests set is empty" do
    include_context "CI mode activated" do
      let(:integration_name) { :rspec }

      let(:early_flake_detection_enabled) { true }
    end

    it "retries the new test 10 times and the flaky test until it passes" do
      rspec_session_run

      expect(test_spans).to have(1).item

      # count how many spans were marked as retries
      retries_count = test_spans.count { |span| span.get_tag("test.is_retry") == "true" }
      expect(retries_count).to eq(0)

      # count how many tests were marked as new
      new_tests_count = test_spans.count { |span| span.get_tag("test.is_new") == "true" }
      expect(new_tests_count).to eq(0)

      expect(test_suite_spans).to have(1).item
      expect(test_suite_spans.first).to have_pass_status

      expect(test_session_span).to have_pass_status
      expect(test_session_span).to have_test_tag(:early_flake_enabled, "true")
      expect(test_session_span).to have_test_tag(:early_flake_abort_reason, "faulty")
    end
  end

  context "session with early flake detection enabled and retrying failed tests enabled" do
    include_context "CI mode activated" do
      let(:integration_name) { :rspec }

      let(:early_flake_detection_enabled) { true }
      let(:unique_tests_set) { Set.new(["SomeTest at ./spec/datadog/ci/contrib/rspec/instrumentation_spec.rb.nested flaky."]) }

      let(:flaky_test_retries_enabled) { true }
    end

    it "retries the new test 10 times and the flaky test until it passes" do
      rspec_session_run(with_flaky_test: true)

      # 1 initial run of flaky test + 4 retries until pass + 1 passing new test + 10 new test retries = 16 spans
      expect(test_spans).to have(16).items

      failed_spans, passed_spans = test_spans.partition { |span| span.get_tag("test.status") == "fail" }
      expect(failed_spans).to have(4).items
      expect(passed_spans).to have(12).items

      test_spans_by_test_name = test_spans.group_by { |span| span.get_tag("test.name") }
      expect(test_spans_by_test_name["nested flaky"]).to have(5).items
      expect(test_spans_by_test_name["nested foo"]).to have(11).item

      # count how many spans were marked as retries
      retries_count = test_spans.count { |span| span.get_tag("test.is_retry") == "true" }
      expect(retries_count).to eq(14)

      # count how many tests were marked as new
      new_tests_count = test_spans.count { |span| span.get_tag("test.is_new") == "true" }
      expect(new_tests_count).to eq(11)

      expect(test_suite_spans).to have(1).item
      expect(test_suite_spans.first).to have_pass_status

      expect(test_session_span).to have_pass_status
      expect(test_session_span).to have_test_tag(:early_flake_enabled, "true")
    end
  end

  context "session with early flake detection enabled and retrying failed tests enabled and both tests are new" do
    include_context "CI mode activated" do
      let(:integration_name) { :rspec }

      let(:early_flake_detection_enabled) { true }
      # avoid bailing out of EFD
      let(:faulty_session_threshold) { 75 }
      let(:unique_tests_set) do
        Set.new(
          [
            "SomeTest at ./spec/datadog/ci/contrib/rspec/instrumentation_spec.rb.nested x."
          ]
        )
      end

      let(:flaky_test_retries_enabled) { true }
    end

    it "retries both tests 10 times" do
      rspec_session_run(with_flaky_test: true)

      # 1 initial run of flaky test + 10 retries + 1 passing new test + 10 new test retries = 22 spans
      expect(test_spans).to have(22).items

      failed_spans, passed_spans = test_spans.partition { |span| span.get_tag("test.status") == "fail" }
      expect(failed_spans).to have(4).items
      expect(passed_spans).to have(18).items

      test_spans_by_test_name = test_spans.group_by { |span| span.get_tag("test.name") }
      expect(test_spans_by_test_name["nested flaky"]).to have(11).items
      expect(test_spans_by_test_name["nested foo"]).to have(11).item

      # count how many spans were marked as retries
      retries_count = test_spans.count { |span| span.get_tag("test.is_retry") == "true" }
      expect(retries_count).to eq(20)

      # count how many tests were marked as new
      new_tests_count = test_spans.count { |span| span.get_tag("test.is_new") == "true" }
      expect(new_tests_count).to eq(22)

      expect(test_suite_spans).to have(1).item
      expect(test_suite_spans.first).to have_pass_status

      expect(test_session_span).to have_pass_status
      expect(test_session_span).to have_test_tag(:early_flake_enabled, "true")
    end
  end

  context "session with early flake detection enabled and both tests are new and faulty percentage is reached" do
    include_context "CI mode activated" do
      let(:integration_name) { :rspec }

      let(:early_flake_detection_enabled) { true }
      let(:faulty_session_threshold) { 30 }
      let(:unique_tests_set) do
        Set.new(
          [
            "SomeTest at ./spec/datadog/ci/contrib/rspec/instrumentation_spec.rb.nested x."
          ]
        )
      end
    end

    it "retries first test only and then bails out of retrying new tests" do
      rspec_session_run(with_flaky_test: true)

      # 1 initial run of passing test + 10 retries + 1 flaky test = 12 spans
      expect(test_spans).to have(12).items

      failed_spans, passed_spans = test_spans.partition { |span| span.get_tag("test.status") == "fail" }
      expect(failed_spans).to have(1).items
      expect(passed_spans).to have(11).items

      test_spans_by_test_name = test_spans.group_by { |span| span.get_tag("test.name") }
      expect(test_spans_by_test_name["nested flaky"]).to have(1).item
      expect(test_spans_by_test_name["nested foo"]).to have(11).items

      # count how many spans were marked as retries
      retries_count = test_spans.count { |span| span.get_tag("test.is_retry") == "true" }
      expect(retries_count).to eq(10)

      # count how many tests were marked as new
      new_tests_count = test_spans.count { |span| span.get_tag("test.is_new") == "true" }
      expect(new_tests_count).to eq(11)

      expect(test_suite_spans).to have(1).item
      expect(test_suite_spans.first).to have_fail_status

      expect(test_session_span).to have_fail_status
      expect(test_session_span).to have_test_tag(:early_flake_enabled, "true")
      expect(test_session_span).to have_test_tag(:early_flake_abort_reason, "faulty")
    end
  end

  context "session with early flake detection enabled and test fails on last retry" do
    include_context "CI mode activated" do
      let(:integration_name) { :rspec }

      let(:early_flake_detection_enabled) { true }
      let(:unique_tests_set) { Set.new(["SomeTest at ./spec/datadog/ci/contrib/rspec/instrumentation_spec.rb.nested foo."]) }

      let(:itr_enabled) { true }
      let(:code_coverage_enabled) { true }
    end

    it "retries the new test 10 times" do
      rspec_session_run(with_flaky_test_that_fails_once: true)

      # 1 passing test + 1 flaky test run + 10 new test retries = 12 spans
      expect(test_spans).to have(12).items

      failed_spans, passed_spans = test_spans.partition { |span| span.get_tag("test.status") == "fail" }
      expect(failed_spans).to have(1).items
      expect(passed_spans).to have(11).items

      test_spans_by_test_name = test_spans.group_by { |span| span.get_tag("test.name") }
      expect(test_spans_by_test_name["nested foo"]).to have(1).item
      expect(test_spans_by_test_name["nested flaky that fails once"]).to have(11).items

      # count how many tests were marked as retries
      retries_count = test_spans.count { |span| span.get_tag("test.is_retry") == "true" }
      expect(retries_count).to eq(10)

      # count how many tests were marked as new
      new_tests_count = test_spans.count { |span| span.get_tag("test.is_new") == "true" }
      expect(new_tests_count).to eq(11)

      expect(test_suite_spans).to have(1).item
      expect(test_suite_spans.first).to have_pass_status

      expect(test_session_span).to have_pass_status
      expect(test_session_span).to have_test_tag(:early_flake_enabled, "true")
    end
  end

  context "session with early flake detection and ITR enabled" do
    include_context "CI mode activated" do
      let(:integration_name) { :rspec }

      let(:early_flake_detection_enabled) { true }
      let(:faulty_session_threshold) { 30 }
      let(:unique_tests_set) do
        Set.new(
          [
            "SomeTest at ./spec/datadog/ci/contrib/rspec/instrumentation_spec.rb.nested x."
          ]
        )
      end

      let(:itr_enabled) { true }
      let(:code_coverage_enabled) { true }
      let(:tests_skipping_enabled) { true }
      let(:itr_skippable_tests) do
        Set.new([
          'SomeTest at ./spec/datadog/ci/contrib/rspec/instrumentation_spec.rb.nested foo.{"arguments":{},"metadata":{"scoped_id":"1:1:1"}}'
        ])
      end
    end

    it "retries first test only and then bails out of retrying new tests" do
      rspec_session_run

      # 1 test skipped by ITR
      expect(test_spans).to have(1).items
      test_span = test_spans.first

      expect(test_span).to have_skip_status
      expect(test_span).not_to have_test_tag(:is_retry)
      # skipped test is not marked as new
      expect(test_span).not_to have_test_tag(:is_new)

      expect(test_suite_spans).to have(1).item
      expect(test_suite_spans.first).to have_skip_status

      expect(test_session_span).to have_pass_status
      expect(test_session_span).to have_test_tag(:early_flake_enabled, "true")
    end
  end
end
