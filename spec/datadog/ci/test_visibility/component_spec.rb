# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/test_visibility/component"

RSpec.describe Datadog::CI::TestVisibility::Component do
  include_context "Telemetry spy"

  shared_examples_for "trace with ciapp-test origin" do
    let(:trace_under_test) { subject }

    it "trace origin is ciapp-test" do
      expect(trace_under_test.origin).to eq(Datadog::CI::Ext::Test::CONTEXT_ORIGIN)
    end
  end

  shared_examples_for "span with environment tags" do
    let(:environment_tags) { Datadog::CI::Ext::Environment.tags(ENV) }
    let(:span_under_test) { subject }

    it "has all the environment tags" do
      environment_tags.each do |key, value|
        expect(span_under_test).to have_test_tag(key, value)
      end
    end
  end

  shared_examples_for "span with default tags" do
    let(:span_under_test) { subject }

    it "span.kind is equal to test" do
      expect(
        span_under_test
      ).to have_test_tag(:span_kind, "test")
    end
  end

  shared_examples_for "span with runtime tags" do
    let(:span_under_test) { subject }

    it "runtime tags are all set" do
      [
        Datadog::CI::Ext::Test::TAG_OS_ARCHITECTURE,
        Datadog::CI::Ext::Test::TAG_OS_PLATFORM,
        Datadog::CI::Ext::Test::TAG_RUNTIME_NAME,
        Datadog::CI::Ext::Test::TAG_RUNTIME_VERSION
      ].each do |tag|
        expect(span_under_test).to have_test_tag(tag)
      end
      expect(span_under_test).to have_test_tag(:command, test_command)
    end
  end

  context "when test suite level visibility is disabled" do
    let(:service) { "my-service" }
    let(:tags) { {"test.framework" => "my-framework", "my.tag" => "my_value"} }

    include_context "CI mode activated" do
      let(:force_test_level_visibility) { true }
    end

    describe "#trace_test_session" do
      subject { test_visibility.start_test_session(service: service, tags: tags) }

      it { is_expected.to be_nil }

      it "does not activate session" do
        expect(test_visibility.active_test_session).to be_nil
      end
    end

    describe "#trace_test_module" do
      let(:module_name) { "my-module" }

      subject { test_visibility.start_test_module(module_name, service: service, tags: tags) }

      it { is_expected.to be_nil }

      it "does not activate module" do
        expect(test_visibility.active_test_module).to be_nil
      end
    end

    describe "#trace_test_suite" do
      let(:suite_name) { "my-module" }

      subject { test_visibility.start_test_suite(suite_name, service: service, tags: tags) }

      it { is_expected.to be_nil }

      it "does not activate test suite" do
        expect(test_visibility.active_test_suite(suite_name)).to be_nil
      end
    end

    describe "#trace" do
      let(:type) { "step" }
      let(:span_name) { "my test step" }
      let(:tags) { {"test.framework" => "my-framework", "my.tag" => "my_value"} }

      context "when given a block" do
        before do
          test_visibility.trace(span_name, type: type, tags: tags) do |span|
            span.set_metric("my.metric", 42)
          end
        end
        subject { span }

        it "traces the block" do
          expect(subject.resource).to eq(span_name)
          expect(subject.type).to eq(type)
        end
      end
    end
  end

  context "when test suite level visibility is enabled" do
    context "without TestOptimisation" do
      include_context "CI mode activated"

      describe "#trace" do
        let(:type) { "step" }
        let(:span_name) { "my test step" }
        let(:tags) { {"test.framework" => "my-framework", "my.tag" => "my_value"} }

        context "when given a block" do
          before do
            test_visibility.trace(span_name, type: type, tags: tags) do |span|
              span.set_metric("my.metric", 42)
            end
          end
          subject { span }

          it "traces the block" do
            expect(subject.resource).to eq(span_name)
            expect(subject.type).to eq(type)
          end

          it "sets the custom metric correctly" do
            expect(subject.get_metric("my.metric")).to eq(42)
          end

          it "sets the tags correctly" do
            expect(subject).to have_test_tag("test.framework", "my-framework")
            expect(subject).to have_test_tag("my.tag", "my_value")
          end

          it_behaves_like "span with environment tags"
          it_behaves_like "span with default tags"
          it_behaves_like "span with runtime tags"
        end

        context "without a block" do
          subject { test_visibility.trace("my test step", type: type, tags: tags) }

          it "returns a new CI span" do
            expect(subject).to be_kind_of(Datadog::CI::Span)
          end

          it "sets the tags correctly" do
            expect(subject).to have_test_tag("test.framework", "my-framework")
            expect(subject).to have_test_tag("my.tag", "my_value")
          end

          it "sets correct resource and span type for the underlying tracer span" do
            subject.finish

            expect(span.resource).to eq(span_name)
            expect(span.type).to eq(type)
          end

          it_behaves_like "span with environment tags"
          it_behaves_like "span with default tags"
          it_behaves_like "span with runtime tags"
        end
      end

      describe "#trace_test" do
        let(:test_name) { "my test" }
        let(:test_suite_name) { "my suite" }
        let(:test_service) { "my-service" }
        let(:tags) { {"test.framework" => "my-framework", "my.tag" => "my_value"} }

        context "without a block" do
          subject do
            test_visibility.trace_test(
              test_name,
              test_suite_name,
              service: test_service,
              tags: tags
            )
          end

          context "when there is no active test session" do
            it "returns a new CI test span" do
              expect(subject).to be_kind_of(Datadog::CI::Test)
              expect(subject.name).to eq(test_name)
              expect(subject.service).to eq(test_service)
              expect(subject.tracer_span.name).to eq(test_name)
              expect(subject.type).to eq(Datadog::CI::Ext::AppTypes::TYPE_TEST)
            end

            it "sets the provided tags correctly" do
              expect(subject).to have_test_tag("test.framework", "my-framework")
              expect(subject).to have_test_tag("my.tag", "my_value")
            end

            it "does not connect the test span to the test session" do
              expect(subject).not_to have_test_tag(:test_session_id)
            end

            it "sets the test suite name as one of the tags" do
              expect(subject).to have_test_tag(:suite, test_suite_name)
              expect(subject).not_to have_test_tag(:test_suite_id)
            end

            it_behaves_like "span with environment tags"
            it_behaves_like "span with default tags"
            it_behaves_like "span with runtime tags"
            it_behaves_like "trace with ciapp-test origin" do
              let(:trace_under_test) do
                subject.finish

                trace
              end
            end
            it_behaves_like "emits telemetry metric", :inc, Datadog::CI::Ext::Telemetry::METRIC_EVENT_CREATED
          end

          context "when there is an active test session" do
            let(:test_session_tags) { {"test.framework_version" => "1.0", "my.session.tag" => "my_session_value"} }
            let(:session_service) { "my-session-service" }
            let(:test_service) { nil }

            let(:test_session) { test_visibility.start_test_session(service: session_service, tags: test_session_tags) }

            before do
              test_session
            end

            context "when there is no active test module" do
              it "returns a new CI test span using service from the test session" do
                expect(subject).to be_kind_of(Datadog::CI::Test)
                expect(subject.name).to eq(test_name)
                expect(subject.service).to eq(session_service)
              end

              it "sets the provided tags correctly while inheriting some tags from the session" do
                expect(subject).to have_test_tag("test.framework", "my-framework")
                expect(subject).to have_test_tag("test.framework_version", "1.0")
                expect(subject).to have_test_tag("my.tag", "my_value")
                expect(subject).not_to have_test_tag("my.session.tag")
              end

              it "connects the test span to the test session" do
                expect(subject).to have_test_tag(:test_session_id, test_session.id.to_s)
              end

              it "starts a new trace" do
                expect(subject.tracer_span.trace_id).not_to eq(test_session.tracer_span.trace_id)
              end

              it_behaves_like "span with environment tags"
              it_behaves_like "span with default tags"
              it_behaves_like "span with runtime tags"

              it_behaves_like "trace with ciapp-test origin" do
                let(:trace_under_test) do
                  subject.finish

                  trace
                end
              end
            end

            context "when there is an active test module" do
              let(:module_name) { "my-module" }

              let(:test_module) do
                test_visibility.start_test_module(module_name)
              end

              before do
                test_module
              end

              it "returns a new CI test span" do
                expect(subject).to be_kind_of(Datadog::CI::Test)
                expect(subject.name).to eq(test_name)
              end

              it "sets the provided tags correctly while inheriting some tags from the session" do
                expect(subject).to have_test_tag("test.framework", "my-framework")
                expect(subject).to have_test_tag("test.framework_version", "1.0")
                expect(subject).to have_test_tag("my.tag", "my_value")
              end

              it "connects the test span to the test module" do
                expect(subject).to have_test_tag(:test_module_id, test_module.id.to_s)
                expect(subject).to have_test_tag(:module, module_name)
              end

              context "when there is an active test suite" do
                let(:test_suite) do
                  test_visibility.start_test_suite(test_suite_name)
                end

                before do
                  test_suite
                end

                it "connects the test span to the test suite" do
                  expect(subject).to have_test_tag(:test_suite_id, test_suite.id.to_s)
                  expect(subject).to have_test_tag(:suite, test_suite_name)
                end
              end

              context "when there is a running test suite but with a different name" do
                let(:test_suite) do
                  test_visibility.start_test_suite("other suite")
                end

                before do
                  test_suite
                end

                it "connects the test span to the running test suite" do
                  expect(subject).to have_test_tag(:test_suite_id, test_suite.id.to_s)
                  expect(subject).to have_test_tag(:suite, "other suite")
                end
              end

              context "when there are several running test suites with different names" do
                before do
                  test_visibility.start_test_suite("other suite")
                  test_visibility.start_test_suite("other other suite")
                end

                it "does not connect test to test suite" do
                  expect(subject).not_to have_test_tag(:test_suite_id)
                end
              end
            end
          end
        end

        context "when given a block" do
          before do
            test_visibility.trace_test(
              test_name,
              test_suite_name,
              service: test_service,
              tags: tags
            ) do |test_span|
              test_span.set_metric("my.metric", 42)
            end
          end
          subject { span }

          it "traces and finishes a test" do
            expect(subject).to have_test_tag(:name, test_name)
            expect(subject.service).to eq(test_service)
            expect(subject.name).to eq(test_name)
            expect(subject.type).to eq(Datadog::CI::Ext::AppTypes::TYPE_TEST)
          end

          it "sets the provided tags correctly" do
            expect(subject).to have_test_tag("test.framework", "my-framework")
            expect(subject).to have_test_tag("my.tag", "my_value")
          end

          it "sets the suite name in tags" do
            expect(subject).to have_test_tag(:suite, test_suite_name)
          end

          it_behaves_like "span with environment tags"
          it_behaves_like "span with default tags"
          it_behaves_like "span with runtime tags"
          it_behaves_like "trace with ciapp-test origin" do
            let(:trace_under_test) do
              trace
            end
          end
          it_behaves_like "emits telemetry metric", :inc, Datadog::CI::Ext::Telemetry::METRIC_EVENT_CREATED
          it_behaves_like "emits telemetry metric", :inc, Datadog::CI::Ext::Telemetry::METRIC_EVENT_FINISHED
        end
      end

      describe "#start_test_session" do
        let(:service) { "my-service" }
        let(:tags) { {"test.framework" => "my-framework", "my.tag" => "my_value"} }

        subject { test_visibility.start_test_session(service: service, tags: tags) }

        it "returns a new CI test_session span" do
          expect(subject).to be_kind_of(Datadog::CI::TestSession)
          expect(subject.name).to eq(test_command)
          expect(subject.service).to eq(service)
          expect(subject.type).to eq(Datadog::CI::Ext::AppTypes::TYPE_TEST_SESSION)
        end

        it "sets the test session id" do
          expect(subject).to have_test_tag(:test_session_id, subject.id.to_s)
        end

        it "sets the provided tags correctly" do
          expect(subject).to have_test_tag("test.framework", "my-framework")
          expect(subject).to have_test_tag("my.tag", "my_value")
        end

        context "with git upload enabled and gitdb api spy" do
          let(:git_metadata_upload_enabled) { true }
          let(:search_commits) { double("search_commits") }
          let(:tags) { {"test.framework" => "my-framework"} }

          it "starts git metadata upload" do
            expect(Datadog::CI::Git::LocalRepository).to receive(:git_commits).and_return(["dcc6f4b112b1f4f21a22deae586f67dc637ba77e"])
            expect(Datadog::CI::Git::SearchCommits).to receive(:new).and_return(search_commits)
            expect(search_commits).to receive(:call) do |repo_url, commits|
              expect(repo_url).to eq("git@github.com:DataDog/datadog-ci-rb.git")

              commits
            end

            subject
          end
        end

        context "with logical test session name set" do
          let(:logical_test_session_name) { "my-logical-test-session" }

          it "sets the logical test session name" do
            subject

            expect(test_visibility.logical_test_session_name).to eq(logical_test_session_name)
          end
        end

        context "without logical test session name set" do
          before do
            allow_any_instance_of(Datadog::CI::TestSession).to receive(:ci_job_name).and_return(ci_job_name)
          end

          context "without CI job name available" do
            let(:ci_job_name) { nil }

            it "uses the test command" do
              subject

              expect(test_visibility.logical_test_session_name).to eq(test_command)
            end
          end

          context "with CI job name available" do
            let(:ci_job_name) { "my-ci-job" }

            it "uses the CI job name and test command" do
              subject

              expect(test_visibility.logical_test_session_name).to eq("#{ci_job_name}-#{test_command}")
            end
          end
        end

        it_behaves_like "span with environment tags"
        it_behaves_like "span with default tags"
        it_behaves_like "span with runtime tags"
        it_behaves_like "trace with ciapp-test origin" do
          let(:trace_under_test) do
            subject.finish

            trace
          end
        end
        it_behaves_like "emits telemetry metric", :inc, Datadog::CI::Ext::Telemetry::METRIC_EVENT_CREATED
        it_behaves_like "emits telemetry metric", :inc, Datadog::CI::Ext::Telemetry::METRIC_TEST_SESSION
      end

      describe "#start_test_module" do
        let(:module_name) { "my-module" }
        let(:service) { "my-service" }
        let(:tags) { {"test.framework" => "my-framework", "my.tag" => "my_value"} }

        subject { test_visibility.start_test_module(module_name, service: service, tags: tags) }

        context "when there is no active test session" do
          it "returns a new CI test_module span" do
            expect(subject).to be_kind_of(Datadog::CI::TestModule)
            expect(subject.name).to eq(module_name)
            expect(subject.service).to eq(service)
            expect(subject.type).to eq(Datadog::CI::Ext::AppTypes::TYPE_TEST_MODULE)
          end

          it "sets the test module id" do
            expect(subject).to have_test_tag(:test_module_id, subject.id.to_s)
          end

          it "sets the test module tag" do
            expect(subject).to have_test_tag(:module, module_name)
          end

          it "doesn't connect the test module span to the test session" do
            expect(subject).not_to have_test_tag(:test_session_id)
          end

          it "sets the provided tags correctly" do
            expect(subject).to have_test_tag("test.framework", "my-framework")
            expect(subject).to have_test_tag("my.tag", "my_value")
          end

          it_behaves_like "span with environment tags"
          it_behaves_like "span with default tags"
          it_behaves_like "span with runtime tags"
          it_behaves_like "trace with ciapp-test origin" do
            let(:trace_under_test) do
              subject.finish

              trace
            end
          end
          it_behaves_like "emits telemetry metric", :inc, Datadog::CI::Ext::Telemetry::METRIC_EVENT_CREATED
        end

        context "when there is an active test session" do
          let(:service) { nil }
          let(:session_service) { "session_service" }
          let(:session_tags) { {"test.framework_version" => "1.0", "my.session.tag" => "my_session_value"} }
          let(:test_session) { test_visibility.start_test_session(service: session_service, tags: session_tags) }

          before do
            test_session
          end

          it "returns a new CI module span using service from the test session" do
            expect(subject).to be_kind_of(Datadog::CI::TestModule)
            expect(subject.name).to eq(module_name)
            expect(subject.service).to eq(session_service)
          end

          it "sets the provided tags correctly while inheriting some tags from the session" do
            expect(subject).to have_test_tag("test.framework", "my-framework")
            expect(subject).to have_test_tag("test.framework_version", "1.0")
            expect(subject).to have_test_tag("my.tag", "my_value")
            expect(subject).not_to have_test_tag("my.session.tag")
          end

          it "connects the test module span to the test session" do
            expect(subject).to have_test_tag(:test_session_id, test_session.id.to_s)
          end

          it "does not start a new trace" do
            expect(subject.tracer_span.trace_id).to eq(test_session.tracer_span.trace_id)
          end
        end
      end

      describe "start_test_suite" do
        let(:module_name) { "my-module" }
        let(:session_service) { "session_service" }
        let(:session_tags) { {"test.framework_version" => "1.0", "my.session.tag" => "my_session_value"} }

        let(:test_session) { test_visibility.start_test_session(service: session_service, tags: session_tags) }
        let(:test_module) { test_visibility.start_test_module(module_name) }

        before do
          test_session
          test_module
        end

        context "when test suite with given name is not started yet" do
          let(:suite_name) { "my-suite" }
          let(:tags) { {"my.tag" => "my_value"} }

          subject { test_visibility.start_test_suite(suite_name, tags: tags) }

          it "returns a new CI test_suite span" do
            expect(subject).to be_kind_of(Datadog::CI::TestSuite)
            expect(subject.name).to eq(suite_name)
            expect(subject.service).to eq(session_service)
            expect(subject.type).to eq(Datadog::CI::Ext::AppTypes::TYPE_TEST_SUITE)
          end

          it "sets the provided tags correctly while inheriting some tags from the session" do
            expect(subject).to have_test_tag("test.framework_version", "1.0")
            expect(subject).to have_test_tag("my.tag", "my_value")
            expect(subject).not_to have_test_tag("my.session.tag")
          end

          it "sets the test suite context" do
            expect(subject).to have_test_tag(:test_suite_id, subject.id.to_s)
            expect(subject).to have_test_tag(:suite, suite_name)
          end

          it "sets test session and test module contexts" do
            expect(subject).to have_test_tag(:test_session_id, test_session.id.to_s)
            expect(subject).to have_test_tag(:test_module_id, test_module.id.to_s)
            expect(subject).to have_test_tag(:module, module_name)
          end

          it_behaves_like "span with environment tags"
          it_behaves_like "span with default tags"
          it_behaves_like "span with runtime tags"
          it_behaves_like "emits telemetry metric", :inc, Datadog::CI::Ext::Telemetry::METRIC_EVENT_CREATED
        end

        context "when test suite with given name is already started" do
          let(:suite_name) { "my-suite" }
          let(:tags) { {"my.tag" => "my_value"} }
          let(:already_running_test_suite) { test_visibility.start_test_suite(suite_name, tags: tags) }

          before do
            already_running_test_suite
          end

          subject { test_visibility.start_test_suite(suite_name) }

          it "returns the already running test suite" do
            expect(subject.id).to eq(already_running_test_suite.id)
            expect(subject).to have_test_tag("my.tag", "my_value")
          end
        end
      end

      describe "#active_test_session" do
        subject { test_visibility.active_test_session }
        context "when there is no active test session" do
          it { is_expected.to be_nil }
        end

        context "when test session is started" do
          let(:test_session) { test_visibility.start_test_session }
          before do
            test_session
          end

          it "returns the active test session" do
            expect(subject).to be(test_session)
          end
        end
      end

      describe "#active_test_module" do
        subject { test_visibility.active_test_module }
        context "when there is no active test module" do
          it { is_expected.to be_nil }
        end

        context "when test module is started" do
          let(:test_module) { test_visibility.start_test_module("my module") }
          before do
            test_module
          end

          it "returns the active test module" do
            expect(subject).to be(test_module)
          end
        end
      end

      describe "#active_test" do
        subject { test_visibility.active_test }

        context "when there is no active test" do
          it { is_expected.to be_nil }
        end

        context "when test is started" do
          let(:ci_test) { test_visibility.trace_test("my test", "my suite") }

          before do
            ci_test
          end

          it "returns the active test" do
            expect(subject).to be(ci_test)
          end
        end
      end

      describe "#active_span" do
        subject { test_visibility.active_span }

        context "when there is no active span" do
          it { is_expected.to be_nil }
        end

        context "when span is started" do
          let(:ci_span) { test_visibility.trace("my test step", type: "step") }

          before do
            ci_span
          end

          it "returns a wrapper around the active tracer span" do
            expect(subject).to be_kind_of(Datadog::CI::Span)
            expect(subject.tracer_span.name).to eq("my test step")
          end
        end
      end

      describe "#deactivate_test" do
        before do
          ci_test
        end

        subject { test_visibility.deactivate_test }

        context "when there is no active test" do
          let(:ci_test) { Datadog::CI::Test.new(double("tracer span")) }

          it { is_expected.to be_nil }
        end

        context "when deactivating the currently active test" do
          let(:ci_test) { test_visibility.trace_test("my test", "my suite") }

          it "deactivates the test" do
            subject

            expect(test_visibility.active_test).to be_nil
          end

          it_behaves_like "emits telemetry metric", :inc, Datadog::CI::Ext::Telemetry::METRIC_EVENT_FINISHED
        end
      end

      describe "#deactivate_test_session" do
        subject { test_visibility.deactivate_test_session }

        context "when there is no active test session" do
          it { is_expected.to be_nil }
        end

        context "when deactivating the currently active test session" do
          before do
            test_visibility.start_test_session
          end

          it "deactivates the test session" do
            subject

            expect(test_visibility.active_test_session).to be_nil
          end

          it_behaves_like "emits telemetry metric", :inc, Datadog::CI::Ext::Telemetry::METRIC_EVENT_FINISHED
        end
      end

      describe "#deactivate_test_module" do
        subject { test_visibility.deactivate_test_module }

        context "when there is no active test module" do
          it { is_expected.to be_nil }
        end

        context "when deactivating the currently active test module" do
          before do
            test_visibility.start_test_module("my module")
          end

          it "deactivates the test module" do
            subject

            expect(test_visibility.active_test_module).to be_nil
          end

          it_behaves_like "emits telemetry metric", :inc, Datadog::CI::Ext::Telemetry::METRIC_EVENT_FINISHED
        end
      end

      describe "#deactivate_test_suite" do
        subject { test_visibility.deactivate_test_suite("my suite") }

        context "when there is no active test suite" do
          it { is_expected.to be_nil }
        end

        context "when deactivating the currently active test suite" do
          before do
            test_visibility.start_test_suite("my suite")
          end

          it "deactivates the test suite" do
            subject

            expect(test_visibility.active_test_suite("my suite")).to be_nil
          end

          it_behaves_like "emits telemetry metric", :inc, Datadog::CI::Ext::Telemetry::METRIC_EVENT_FINISHED
        end
      end
    end

    context "with TestOptimisation" do
      context "without require_git in settings response" do
        include_context "CI mode activated" do
          let(:itr_enabled) { true }
          let(:tests_skipping_enabled) { true }
          let(:code_coverage_enabled) { true }
        end

        describe "#start_test_session" do
          let(:service) { "my-service" }
          let(:tags) { {"test.framework" => "my-framework", "my.tag" => "my_value"} }

          subject { test_visibility.start_test_session(service: service, tags: tags) }

          it "returns a new CI test_session span with ITR/TestOptimisation tags" do
            expect(subject).to be_kind_of(Datadog::CI::TestSession)
            expect(subject.service).to eq(service)

            expect(subject.skipping_tests?).to be true
            expect(subject.code_coverage?).to be true
          end
        end
      end

      context "with require_git in settings response" do
        include_context "CI mode activated" do
          let(:itr_enabled) { true }
          let(:tests_skipping_enabled) { true }
          let(:code_coverage_enabled) { true }
          let(:require_git) { true }
        end

        describe "#start_test_session" do
          let(:service) { "my-service" }
          let(:tags) { {"test.framework" => "my-framework", "my.tag" => "my_value"} }

          subject { test_visibility.start_test_session(service: service, tags: tags) }

          it { is_expected.not_to be_skipping_tests }
        end
      end
    end
  end
end
