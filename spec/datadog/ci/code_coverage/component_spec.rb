# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/code_coverage/component"

RSpec.describe Datadog::CI::CodeCoverage::Component do
  subject(:component) { described_class.new(enabled: enabled, transport: transport, flags: coverage_flags) }

  let(:coverage_flags) { nil }
  let(:enabled) { true }
  let(:transport) { instance_double(Datadog::CI::CodeCoverage::Transport, send_coverage_report: http_response) }
  let(:http_response) do
    instance_double(
      Datadog::CI::Transport::Adapters::Net::Response,
      ok?: true
    )
  end

  let(:environment_tags) do
    {
      "git.repository_url" => "https://github.com/example/repo",
      "git.branch" => "main",
      "git.commit.sha" => "abc123def456789012345678901234567890abcd",
      "ci.provider.name" => "github",
      "ci.pipeline.id" => "12345",
      "ci.workspace_path" => "/home/user/project"
    }
  end

  let(:serialized_report) { '{"app/file.rb":[1,2,null,3]}' }

  before do
    allow(Datadog::CI::Ext::Environment).to receive(:tags).with(ENV).and_return(environment_tags)
  end

  describe "#initialize" do
    context "when enabled is true" do
      it "sets enabled to true" do
        expect(component.enabled).to be true
      end
    end

    context "when enabled is false" do
      let(:enabled) { false }

      it "sets enabled to false" do
        expect(component.enabled).to be false
      end
    end
  end

  describe "#configure" do
    let(:library_configuration) do
      instance_double(
        Datadog::CI::Remote::LibrarySettings,
        coverage_report_upload_enabled?: coverage_report_upload_enabled
      )
    end

    context "when coverage_report_upload_enabled is true in remote settings" do
      let(:coverage_report_upload_enabled) { true }

      it "keeps enabled as true" do
        expect(component.enabled).to be true

        component.configure(library_configuration)

        expect(component.enabled).to be true
      end
    end

    context "when coverage_report_upload_enabled is false in remote settings" do
      let(:coverage_report_upload_enabled) { false }

      it "sets enabled to false" do
        expect(component.enabled).to be true

        component.configure(library_configuration)

        expect(component.enabled).to be false
      end
    end

    context "when component is already disabled" do
      let(:enabled) { false }
      let(:coverage_report_upload_enabled) { true }

      it "keeps enabled as false even if remote settings is true" do
        expect(component.enabled).to be false

        component.configure(library_configuration)

        expect(component.enabled).to be false
      end
    end
  end

  describe "#upload" do
    let(:format) { "simplecov-internal" }

    context "when enabled" do
      it "builds event with environment tags" do
        expect(transport).to receive(:send_coverage_report) do |args|
          event = args[:event]
          expect(event["type"]).to eq("coverage_report")
          expect(event["format"]).to eq("simplecov-internal")
          expect(event["git.repository_url"]).to eq("https://github.com/example/repo")
          expect(event["git.branch"]).to eq("main")
          expect(event["git.commit.sha"]).to eq("abc123def456789012345678901234567890abcd")
          expect(event["ci.provider.name"]).to eq("github")
          expect(event["ci.pipeline.id"]).to eq("12345")
          expect(event["ci.workspace_path"]).to eq("/home/user/project")
        end

        component.upload(serialized_report: serialized_report, format: format)
      end

      it "uses the provided format in the event" do
        expect(transport).to receive(:send_coverage_report) do |args|
          event = args[:event]
          expect(event["format"]).to eq("custom-format")
        end

        component.upload(serialized_report: serialized_report, format: "custom-format")
      end

      it "passes the serialized report directly to transport" do
        expect(transport).to receive(:send_coverage_report) do |args|
          expect(args[:coverage_report]).to eq(serialized_report)
        end

        component.upload(serialized_report: serialized_report, format: format)
      end

      it "returns the response from transport" do
        expect(component.upload(serialized_report: serialized_report, format: format)).to eq(http_response)
      end

      context "when coverage report flags are set" do
        let(:coverage_flags) { +"type:unit-tests,jvm-21" }

        it "adds them to the event" do
          expect(transport).to receive(:send_coverage_report) do |args|
            expect(args[:event]["report.flags"]).to eq(["type:unit-tests", "jvm-21"])
          end

          component.upload(serialized_report: serialized_report, format: format)
        end

        context "with whitespace, empty entries, and duplicates" do
          let(:coverage_flags) { " type:unit-tests, ,jvm-21,type:unit-tests, " }

          it "trims whitespace and empty entries while preserving order and duplicates" do
            expect(transport).to receive(:send_coverage_report) do |args|
              expect(args[:event]["report.flags"]).to eq(["type:unit-tests", "jvm-21", "type:unit-tests"])
            end

            component.upload(serialized_report: serialized_report, format: format)
          end
        end

        context "with exactly the maximum number of flags" do
          let(:flags) { Array.new(described_class::MAX_REPORT_FLAGS) { |index| "flag-#{index}" } }
          let(:coverage_flags) { flags.join(",") }

          it "adds every flag to the event" do
            expect(transport).to receive(:send_coverage_report) do |args|
              expect(args[:event]["report.flags"]).to eq(flags)
            end

            component.upload(serialized_report: serialized_report, format: format)
          end
        end

        context "with more than the maximum number of flags" do
          let(:flags) { Array.new(described_class::MAX_REPORT_FLAGS + 1) { |index| "flag-#{index}" } }
          let(:coverage_flags) { flags.join(",") }

          before do
            allow(Datadog.logger).to receive(:warn)
          end

          it "warns once, omits the flags, and uploads the report" do
            responses = 2.times.map do
              component.upload(serialized_report: serialized_report, format: format)
            end

            expect(responses).to eq([http_response, http_response])
            expect(Datadog.logger).to have_received(:warn).once.with(
              "DD_CODE_COVERAGE_FLAGS contains 33 flags, but only 32 are allowed; omitting report flags"
            )
            expect(transport).to have_received(:send_coverage_report).twice do |args|
              expect(args[:event]).not_to have_key("report.flags")
            end
          end
        end

        it "snapshots flags when the component is created" do
          original_component = component
          coverage_flags.replace("changed")

          2.times do
            original_component.upload(serialized_report: serialized_report, format: format)
          end

          expect(transport).to have_received(:send_coverage_report).twice do |args|
            expect(args[:event]["report.flags"]).to eq(["type:unit-tests", "jvm-21"])
          end
        end
      end

      context "when coverage report flags contain no values" do
        {
          "flags are nil" => nil,
          "flags are empty" => "",
          "flags contain only whitespace and commas" => " ,  , "
        }.each do |description, value|
          context description do
            let(:coverage_flags) { value }

            it "omits report.flags from the event" do
              expect(transport).to receive(:send_coverage_report) do |args|
                expect(args[:event]).not_to have_key("report.flags")
              end

              component.upload(serialized_report: serialized_report, format: format)
            end
          end
        end
      end
    end

    context "when disabled" do
      let(:enabled) { false }

      it "does not send coverage report" do
        expect(transport).not_to receive(:send_coverage_report)

        component.upload(serialized_report: serialized_report, format: format)
      end

      it "returns nil" do
        expect(component.upload(serialized_report: serialized_report, format: format)).to be_nil
      end
    end

    context "when serialized_report is nil" do
      it "does not send coverage report" do
        expect(transport).not_to receive(:send_coverage_report)

        component.upload(serialized_report: nil, format: format)
      end
    end
  end

  describe "#shutdown!" do
    it "does nothing (synchronous transport)" do
      expect { component.shutdown! }.not_to raise_error
    end
  end
end
