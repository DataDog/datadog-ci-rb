# frozen_string_literal: true

require "time"
require "stringio"
require "ostruct"

# Require Rails components needed by rswag-specs
require "rails"
require "action_controller/railtie"

# Create a minimal Rails application for rswag
class TestApp < Rails::Application
  config.eager_load = false
  config.logger = Logger.new(nil)
  config.secret_key_base = "test_secret_key_base_for_rswag_specs"

  # Enable request forgery protection bypass for testing
  config.action_controller.allow_forgery_protection = false
end

# Define namespace modules
module Api
  module V1
  end
end

# Define a simple API controller
class Api::V1::UsersController < ActionController::API
  def index
    render json: [{id: 1, name: "Test User"}], status: :ok
  end

  def create
    render json: {id: 2, name: params[:name]}, status: :created
  end
end

class Api::V1::ArticlesController < ActionController::API
  def index
    render json: [{id: 1, title: "Test Article"}], status: :ok
  end
end

# Define routes
Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resources :users, only: [:index, :create]
      resources :articles, only: [:index]
    end
  end
end

# Initialize the Rails app
Rails.application.initialize!

# Now we can require rswag-specs
require "rswag/specs"

RSpec.describe "RSpec instrumentation with rswag" do
  let(:integration) { Datadog::CI::Contrib::Instrumentation.fetch_integration(:rspec) }

  before do
    # expect that public manual API isn't used
    expect(Datadog::CI).to receive(:start_test_session).never
    expect(Datadog::CI).to receive(:start_test_module).never
    expect(Datadog::CI).to receive(:start_test_suite).never
    expect(Datadog::CI).to receive(:start_test).never
  end

  # Runs a regular RSpec test (not dynamically generated) for comparison
  def regular_rspec_session_run
    with_new_rspec_environment do
      spec = RSpec.describe "Regular RSpec Tests" do
        it "is a regular test" do
          expect(1 + 1).to eq(2)
        end
      end

      options = ::RSpec::Core::ConfigurationOptions.new(%w[--pattern none --format documentation])

      stdout = StringIO.new
      stderr = StringIO.new
      ::RSpec::Core::Runner.new(options).run(stderr, stdout)

      OpenStruct.new(spec: spec, stdout: stdout, stderr: stderr)
    end
  end

  def rswag_session_run(with_failed_test: false)
    with_new_rspec_environment do
      spec = RSpec.describe "API Tests", type: :request do
        # Include Rails integration test modules
        include ActionDispatch::Integration::Runner
        include ActionDispatch::Assertions

        # Extend with rswag helpers
        extend Rswag::Specs::ExampleGroupHelpers
        include Rswag::Specs::ExampleHelpers

        # rswag needs access to the Rails app for making requests
        let(:app) { Rails.application }

        path "/api/v1/users" do
          get "retrieves all users" do
            tags "Users"
            produces "application/json"

            response "200", "users found" do
              run_test!
            end
          end

          post "creates a user" do
            tags "Users"
            consumes "application/json"
            produces "application/json"

            parameter name: :user, in: :body, schema: {
              type: :object,
              properties: {
                name: {type: :string}
              }
            }

            let(:user) { {name: "New User"} }

            response "201", "user created" do
              run_test!
            end
          end
        end

        path "/api/v1/articles" do
          get "lists articles" do
            tags "Articles"
            produces "application/json"

            response "200", "articles found" do
              run_test!
            end
          end
        end

        if with_failed_test
          path "/api/v1/users" do
            get "fails with wrong status" do
              tags "Users"
              produces "application/json"

              # Expect 404 but endpoint returns 200, so this will fail
              response "404", "not found" do
                run_test!
              end
            end
          end
        end
      end

      options = ::RSpec::Core::ConfigurationOptions.new(%w[--pattern none --format documentation])

      stdout = StringIO.new
      stderr = StringIO.new
      ::RSpec::Core::Runner.new(options).run(stderr, stdout)

      OpenStruct.new(spec: spec, stdout: stdout, stderr: stderr)
    end
  end

  context "with rswag tests using run_test!" do
    include_context "CI mode activated" do
      let(:integration_name) { :rspec }
      let(:integration_options) { {service_name: "rswag-test"} }
    end

    it "creates test session span" do
      rswag_session_run

      expect(test_session_span).not_to be_nil

      expect(test_session_span.type).to eq("test_session_end")
      expect(test_session_span).to have_test_tag(:span_kind, "test")
      expect(test_session_span).to have_test_tag(:framework, "rspec")
      expect(test_session_span).to have_test_tag(
        :framework_version,
        integration.version.to_s
      )
    end

    it "creates test module span" do
      rswag_session_run

      expect(test_module_span).not_to be_nil

      expect(test_module_span.type).to eq("test_module_end")
      expect(test_module_span.name).to eq("rspec")

      expect(test_module_span).to have_test_tag(:span_kind, "test")
      expect(test_module_span).to have_test_tag(:framework, "rspec")
      expect(test_module_span).to have_test_tag(
        :framework_version,
        integration.version.to_s
      )
    end

    it "creates test suite span with correct source file tag" do
      result = rswag_session_run
      spec = result.spec

      expect(first_test_suite_span).not_to be_nil

      expect(first_test_suite_span.type).to eq("test_suite_end")
      expect(first_test_suite_span.name).to eq("API Tests at #{spec.file_path}")

      expect(first_test_suite_span).to have_test_tag(:span_kind, "test")
      expect(first_test_suite_span).to have_test_tag(:framework, "rspec")
      expect(first_test_suite_span).to have_test_tag(
        :framework_version,
        integration.version.to_s
      )

      # This is the critical assertion - source_file should NOT be empty
      expect(first_test_suite_span).to have_test_tag(
        :source_file,
        "spec/datadog/ci/contrib/rswag_rspec/instrumentation_spec.rb"
      )
      expect(first_test_suite_span.get_tag(Datadog::CI::Ext::Test::TAG_SOURCE_FILE)).not_to be_empty
    end

    it "creates test spans with correct tags including non-empty source_file" do
      rswag_session_run

      expect(test_spans).to have(3).items

      test_spans.each do |test_span|
        expect(test_span.type).to eq(Datadog::CI::Ext::AppTypes::TYPE_TEST)
        expect(test_span.service).to eq("rswag-test")

        expect(test_span).to have_test_tag(:span_kind, "test")
        expect(test_span).to have_test_tag(:type, "test")
        expect(test_span).to have_test_tag(:framework, "rspec")
        expect(test_span).to have_test_tag(
          :framework_version,
          integration.version.to_s
        )

        # Critical assertion: source_file must NOT be empty
        # This is the bug we're testing - rswag's run_test! produces empty source_file
        source_file = test_span.get_tag(Datadog::CI::Ext::Test::TAG_SOURCE_FILE)
        expect(source_file).not_to be_nil, "test.source.file tag should not be nil"
        expect(source_file).not_to be_empty, "test.source.file tag should not be empty"
        expect(source_file).to eq("spec/datadog/ci/contrib/rswag_rspec/instrumentation_spec.rb")

        # source_start should be present and point to a line in this spec file
        expect(test_span).to have_test_tag(:source_start)
        source_start = test_span.get_tag(Datadog::CI::Ext::Test::TAG_SOURCE_START)
        expect(source_start).not_to be_nil
        expect(source_start.to_i).to be > 0
      end
    end

    it "has source_start pointing to the spec file, not the rswag gem" do
      rswag_session_run

      # rswag's run_test! generates examples at line 143 in example_group_helpers.rb
      # Our fix should resolve source_start to the parent example_group in the spec file
      rswag_gem_line = 143

      test_spans.each do |test_span|
        source_start = test_span.get_tag(Datadog::CI::Ext::Test::TAG_SOURCE_START).to_i

        # The line number should NOT be from the rswag gem (line 143)
        expect(source_start).not_to eq(rswag_gem_line),
          "source_start should not be #{rswag_gem_line} (rswag gem internal line)"

        # The line number should be within a reasonable range for the spec file
        # The rswag test definitions (response blocks) are around lines 85-140
        expect(source_start).to be_between(60, 200),
          "source_start #{source_start} should be within the spec file range (60-200)"
      end
    end

    it "does not set source_end for dynamically generated tests" do
      rswag_session_run

      # When source location is resolved from parent example_group (as with rswag tests),
      # source_end should not be set because @example_block is in a different file (the gem)
      test_spans.each do |test_span|
        source_end = test_span.get_tag(Datadog::CI::Ext::Test::TAG_SOURCE_END)

        expect(source_end).to be_nil,
          "source_end should not be set for dynamically generated tests (rswag)"
      end
    end

    it "sets source_end for regular (non-dynamically generated) RSpec tests" do
      regular_rspec_session_run

      # Regular RSpec tests should have source_end set because they are defined
      # in the spec file itself (not dynamically generated by a gem)
      test_spans.each do |test_span|
        source_end = test_span.get_tag(Datadog::CI::Ext::Test::TAG_SOURCE_END)

        expect(source_end).not_to be_nil,
          "source_end should be set for regular RSpec tests"
        expect(source_end.to_i).to be > 0,
          "source_end should be a positive line number"
      end
    end

    it "creates spans for rswag path/operation structure" do
      rswag_session_run

      # Verify the test names match rswag's DSL structure
      test_names = test_spans.map(&:name)

      # rswag generates test names from path + operation + response description
      expect(test_names).to include(match(/users found/))
      expect(test_names).to include(match(/user created/))
      expect(test_names).to include(match(/articles found/))
    end

    it "connects all tests to the session, module, and suite" do
      rswag_session_run

      test_spans.each do |test_span|
        expect(test_span).to have_test_tag(:test_session_id, test_session_span.id.to_s)
        expect(test_span).to have_test_tag(:test_module_id, test_module_span.id.to_s)
        expect(test_span).to have_test_tag(:test_suite_id, first_test_suite_span.id.to_s)
      end
    end

    context "with failures" do
      it "creates test session span with failed state" do
        rswag_session_run(with_failed_test: true)

        expect(test_session_span).to have_fail_status
      end

      it "creates test suite span with failed state" do
        rswag_session_run(with_failed_test: true)

        expect(first_test_suite_span).to have_fail_status
      end

      it "still has non-empty source_file on failed tests" do
        rswag_session_run(with_failed_test: true)

        failed_test = test_spans.find { |span| span.get_tag("test.status") == "fail" }
        expect(failed_test).not_to be_nil

        source_file = failed_test.get_tag(Datadog::CI::Ext::Test::TAG_SOURCE_FILE)
        expect(source_file).not_to be_nil, "test.source.file tag should not be nil on failed test"
        expect(source_file).not_to be_empty, "test.source.file tag should not be empty on failed test"
      end
    end
  end

  context "with code coverage collected" do
    before { skip if PlatformHelpers.jruby? }

    include_context "CI mode activated" do
      let(:integration_name) { :rspec }
      let(:integration_options) { {service_name: "rswag-test"} }

      let(:itr_enabled) { true }
      let(:code_coverage_enabled) { true }
    end

    it "collects code coverage with valid source files" do
      rswag_session_run

      expect(test_session_span).not_to be_nil
      expect(test_session_span).to have_test_tag(:code_coverage_enabled, "true")

      expect(test_spans).to have(3).items
      expect(coverage_events).to have(3).items

      expect_coverage_events_belong_to_session(test_session_span)
      expect_coverage_events_belong_to_suite(first_test_suite_span)
      expect_coverage_events_belong_to_tests(test_spans)
    end
  end

  context "when skipping tests with ITR" do
    include_context "CI mode activated" do
      let(:integration_name) { :rspec }
      let(:integration_options) { {service_name: "rswag-test"} }

      let(:itr_enabled) { true }
      let(:tests_skipping_enabled) { true }

      let(:test_management_enabled) { true }
    end

    context "skipped a single test" do
      let(:itr_skippable_tests) do
        Set.new([
          'API Tests at ./spec/datadog/ci/contrib/rswag_rspec/instrumentation_spec.rb./api/v1/users get retrieves all users 200 users found.{"arguments":{},"metadata":{"scoped_id":"1:1:1:1:1"}}'
        ])
      end

      it "skipped test still reports correct source_file" do
        rswag_session_run

        skipped_test = test_spans.find { |span| span.get_tag("test.status") == "skip" }

        if skipped_test
          source_file = skipped_test.get_tag(Datadog::CI::Ext::Test::TAG_SOURCE_FILE)
          expect(source_file).not_to be_nil
          expect(source_file).not_to be_empty
        end
      end
    end
  end
end
