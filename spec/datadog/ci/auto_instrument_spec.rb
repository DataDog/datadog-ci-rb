# frozen_string_literal: true

RSpec.describe "Datadog CI auto instrumentation entrypoint" do
  subject(:load_entrypoint) { load File.expand_path("../../../lib/datadog/ci/auto_instrument.rb", __dir__) }

  it "keeps activation available to an exec'ing launcher" do
    ClimateControl.modify("RUBYOPT" => "-rbundler/setup -rdatadog/ci/auto_instrument -W:no-deprecated") do
      expect(Datadog::CI::Contrib::Instrumentation).to receive(:auto_instrument)

      load_entrypoint

      expect(ENV.fetch("RUBYOPT")).to eq("-rbundler/setup -rdatadog/ci/auto_instrument -W:no-deprecated")
    end
  end
end
