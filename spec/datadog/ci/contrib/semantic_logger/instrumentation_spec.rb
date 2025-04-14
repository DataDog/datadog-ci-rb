require "action_controller/railtie"
require "action_view/railtie"
require "rails/test_unit/railtie"

require "rails_semantic_logger"

require_relative "../../../../support/contexts/rails_test_app"

RSpec.describe "SemanticLogger instrumentation" do
  include_context "Rails test app" do
    let(:routes) do
      {"/logging" => "logging_test#index"}
    end

    let(:controllers) do
      [logging_test_controller]
    end

    let(:logging_test_controller) do
      stub_const(
        "LoggingTestController",
        Class.new(ActionController::Base) do
          def index
            ::Rails.logger.info "MY VOICE SHALL BE HEARD!"

            render plain: "OK"
          end
        end
      )
    end
  end

  include_context "CI mode activated" do
    let(:integration_name) { :minitest }

    let(:agentless_mode_enabled) { true }
    let(:agentless_logs_enabled) { true }
    let(:api_key) { "dd-api-key" }
  end

  before do
    app # Initialize app before enabling log injection
    Datadog.configure do |c|
      c.tracing.log_injection = true
      c.tracing.instrument :semantic_logger
    end

    Minitest::Runnable.reset
    require_relative "test/test_logging"
    Minitest.run([])
  end

  it "instruments the test session with agentless logs support" do
    # test session and module traced
    expect(test_session_span).not_to be_nil
    expect(test_module_span).not_to be_nil

    expect([test_session_span, test_module_span]).to all have_pass_status

    expect(test_suite_spans).to have(1).items
    expect(test_suite_spans).to have_tag_values_no_order(:status, ["pass"])
    expect(test_suite_spans).to have_tag_values_no_order(
      :suite,
      [
        "LoggingTest at spec/datadog/ci/contrib/semantic_logger/test/test_logging.rb"
      ]
    )

    # there is test span for every test case
    expect(test_spans).to have(1).item

    test_span = test_spans.first
    expect(test_span.name).to eq("test_gets_logging")
    expect(test_span).to have_test_tag(:test_suite_id)
    expect(test_span).to have_test_tag(:test_module_id)
    expect(test_span).to have_test_tag(:test_session_id)

    expect(agentless_logs).to have(9).items

    log = agentless_logs.find { |l| l[:message] == "MY VOICE SHALL BE HEARD!" }
    expect(log).not_to be_nil
    expect(log[:name]).to eq("Rails")
    expect(log[:level]).to eq(:info)
    expect(log[:named_tags][:dd][:trace_id]).to eq(test_span.trace_id.to_s)
    expect(log[:named_tags][:dd][:service]).to eq("rails_test")
  end
end
