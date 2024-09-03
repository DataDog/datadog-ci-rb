# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/remote/component"

RSpec.describe Datadog::CI::Remote::Component do
  subject(:component) { described_class.new(library_settings_client: library_settings_client) }

  let(:library_settings_client) { instance_double(Datadog::CI::Remote::LibrarySettingsClient) }
  let(:git_tree_upload_worker) { instance_double(Datadog::CI::Worker) }
  let(:test_optimisation) { instance_double(Datadog::CI::TestOptimisation::Component) }
  let(:test_retries) { instance_double(Datadog::CI::TestRetries::Component) }

  before do
    allow(Datadog.send(:components)).to receive(:git_tree_upload_worker).and_return(git_tree_upload_worker)
    allow(Datadog.send(:components)).to receive(:test_optimisation).and_return(test_optimisation)
    allow(Datadog.send(:components)).to receive(:test_retries).and_return(test_retries)
  end

  describe "#configure" do
    subject { component.configure(test_session) }

    let(:test_session) { instance_double(Datadog::CI::TestSession) }
    let(:library_configuration) do
      instance_double(Datadog::CI::Remote::LibrarySettings, require_git?: require_git)
    end

    before do
      expect(library_settings_client).to receive(:fetch)
        .with(test_session).and_return(library_configuration).once
    end

    context "git upload is not required" do
      let(:require_git) { false }

      before do
        expect(test_optimisation).to receive(:configure).with(library_configuration, test_session)
        expect(test_retries).to receive(:configure).with(library_configuration, test_session)
      end

      it { subject }
    end

    context "git upload is required" do
      let(:require_git) { true }

      before do
        expect(git_tree_upload_worker).to receive(:wait_until_done)
        expect(library_settings_client).to receive(:fetch)
          .with(test_session).and_return(library_configuration)

        expect(test_optimisation).to receive(:configure).with(library_configuration, test_session)
        expect(test_retries).to receive(:configure).with(library_configuration, test_session)
      end

      it { subject }
    end
  end
end
