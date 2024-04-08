# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/git/upload_packfile"

RSpec.describe Datadog::CI::Git::UploadPackfile do
  let(:api) { double("api") }

  subject(:upload_packfile) do
    described_class.new(api: api, head_commit_sha: "HEAD", repository_url: "https://datadoghq.com/git/test.git")
  end

  describe "#call" do
    let(:filepath) { "nonexistent" }

    context "when the API is not configured" do
      let(:api) { nil }

      it "raises an error" do
        expect { upload_packfile.call(filepath: filepath) }
          .to raise_error(Datadog::CI::Git::UploadPackfile::ApiError, "test visibility API is not configured")
      end
    end

    context "when the API is configured" do
      before do
        allow(api).to receive(:api_request).and_return(http_response)
      end
      let(:http_response) { double("http_response", ok?: true) }

      context "when file does not exist" do
        it "raises an error" do
          expect { upload_packfile.call(filepath: filepath) }
            .to raise_error(
              Datadog::CI::Git::UploadPackfile::ApiError,
              "Failed to read packfile: No such file or directory @ rb_sysopen - nonexistent"
            )
        end
      end

      context "when file exists" do
        let(:tmpdir) { Dir.mktmpdir }
        let(:filepath) { "#{tmpdir}/packfile.idx" }

        before do
          File.write(filepath, "packfile contents")
        end

        after do
          FileUtils.remove_entry(tmpdir)
        end

        context "when the API request fails" do
          let(:http_response) { double("http_response", ok?: false, inspect: "error message") }

          it "raises an error" do
            expect { upload_packfile.call(filepath: filepath) }
              .to raise_error(Datadog::CI::Git::UploadPackfile::ApiError, "Failed to upload packfile: error message")
          end
        end

        context "when the API request is successful" do
          before do
            allow(SecureRandom).to receive(:uuid).and_return("boundary")
          end

          it "uploads the packfile" do
            expect(api).to receive(:api_request).with(
              path: Datadog::CI::Ext::Transport::DD_API_GIT_UPLOAD_PACKFILE_PATH,
              payload: [
                "--boundary",
                'Content-Disposition: form-data; name="pushedSha"',
                "Content-Type: application/json",
                "",
                {data: {id: "HEAD", type: "commit"}, meta: {repository_url: "https://datadoghq.com/git/test.git"}}.to_json,
                "--boundary",
                'Content-Disposition: form-data; name="packfile"; filename="packfile.idx"',
                "Content-Type: application/octet-stream",
                "",
                "packfile contents",
                "--boundary--"
              ].join("\r\n"),
              headers: {Datadog::CI::Ext::Transport::HEADER_CONTENT_TYPE => "multipart/form-data; boundary=boundary"}
            ).and_return(http_response)

            upload_packfile.call(filepath: filepath)
          end
        end
      end
    end
  end
end
