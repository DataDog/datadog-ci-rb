# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/logs/component"

RSpec.describe Datadog::CI::Logs::Component do
  subject(:component) { described_class.new(enabled: enabled, writer: writer) }

  let(:test_session) { instance_double(Datadog::CI::TestSession, service: "test-service") }
  let(:test_visibility) { instance_double(Datadog::CI::TestVisibility::Component, active_test_session: test_session) }
  let(:components) { double(:components, test_visibility: test_visibility) }

  let(:enabled) { true }
  let(:writer) { instance_double(Datadog::CI::AsyncWriter, write: true, stop: true) }
  let(:event) { {level: "INFO", message: "test message"} }

  before do
    allow(Datadog::Core::Environment::Platform).to receive(:hostname).and_return("test-hostname")
    allow(Datadog).to receive(:send).with(:components).and_return(components)
  end

  describe "#initialize" do
    context "when enabled is true and writer is present" do
      it "sets enabled to true" do
        expect(component.enabled).to be true
      end
    end

    context "when enabled is true but writer is nil" do
      let(:writer) { nil }

      it "automatically disables the component" do
        expect(component.enabled).to be false
      end
    end

    context "when enabled is false" do
      let(:enabled) { false }

      it "sets enabled to false" do
        expect(component.enabled).to be false
      end
    end
  end

  describe "#write" do
    context "when enabled" do
      it "adds common tags to the event" do
        allow(writer).to receive(:write).with(event)

        component.write(event)

        expect(event[:ddsource]).to eq("ruby")
        expect(event[:ddtags]).to eq("datadog.product:citest")
        expect(event[:service]).to eq("test-service")
        expect(event[:hostname]).to eq("test-hostname")
      end

      it "writes the event to the writer" do
        expected_event = event.dup

        expect(writer).to receive(:write) do |arg|
          expect(arg).to include(
            level: "INFO",
            message: "test message",
            ddsource: "ruby",
            ddtags: "datadog.product:citest",
            service: "test-service",
            hostname: "test-hostname"
          )
        end

        component.write(expected_event)
      end

      it "doesn't override existing tag values" do
        custom_event = {
          ddsource: "custom-source",
          ddtags: "custom-tags",
          service: "custom-service",
          hostname: "custom-hostname"
        }

        expect(writer).to receive(:write).with(custom_event)

        component.write(custom_event)

        expect(custom_event[:ddsource]).to eq("custom-source")
        expect(custom_event[:ddtags]).to eq("custom-tags")
        expect(custom_event[:service]).to eq("custom-service")
        expect(custom_event[:hostname]).to eq("custom-hostname")
      end

      it "returns nil" do
        allow(writer).to receive(:write).with(event)

        expect(component.write(event)).to be_nil
      end
    end

    context "when disabled" do
      let(:enabled) { false }

      it "doesn't write events" do
        expect(writer).not_to receive(:write)

        component.write(event)
      end

      it "returns nil" do
        expect(component.write(event)).to be_nil
      end
    end
  end

  describe "#shutdown!" do
    it "stops the writer" do
      expect(writer).to receive(:stop)

      component.shutdown!
    end
  end
end
