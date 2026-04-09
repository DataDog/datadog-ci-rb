require "minitest/queue/runner"
require "fileutils"
require "securerandom"
require "json"
require "cgi"

RSpec.describe "Minitest instrumentation with Shopify's ci-queue runner" do
  include_context "CI mode activated" do
    let(:integration_name) { :minitest }
    let(:integration_options) { {service_name: "ltest"} }
  end

  let(:run_id) { SecureRandom.random_number(2**64 - 1) }
  let(:fake_test_file_path) { File.expand_path("spec/datadog/ci/contrib/ci_queue_minitest/fake_test.rb") }

  before do
    Minitest::Runnable.reset
    FileUtils.mkdir("log")

    queue_entries = %w[test_pass test_pass_other test_fail].map do |method|
      CGI.escape(JSON.dump({test_id: "SomeTest##{method}", file_path: fake_test_file_path}))
    end

    Minitest::Queue::Runner.invoke(
      [
        "-Ispec/datadog/ci/contrib/ci_queue_minitest",
        "--build",
        run_id.to_s,
        "--worker",
        "1",
        "--queue",
        "list:#{queue_entries.join(":")}",
        "run",
        "spec/datadog/ci/contrib/ci_queue_minitest/fake_test.rb"
      ]
    )

    Minitest.run([])
  end

  after do
    FileUtils.rm_rf("log")
  end

  it "instruments this minitest session" do
    # test session and module traced
    expect(test_session_span).not_to be_nil
    expect(test_module_span).not_to be_nil

    # test session and module are failed
    expect([test_session_span, test_module_span]).to all have_fail_status

    # there is a single test suite
    expect(test_suite_spans).to have(1).item
    expect(test_suite_spans.first).to have_fail_status
    expect(test_suite_spans).to have_tag_values_no_order(
      :suite,
      [
        "SomeTest at spec/datadog/ci/contrib/ci_queue_minitest/fake_test.rb"
      ]
    )

    # there is test span for every test case
    expect(test_spans).to have(3).items
    # there is a single test suite
    expect(test_spans).to have_unique_tag_values_count(:test_suite_id, 1)

    # every test span is connected to test module and test session
    expect(test_spans).to all have_test_tag(:test_module_id)
    expect(test_spans).to all have_test_tag(:test_session_id)
  end
end
