# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/test_retries/null_component"

RSpec.describe Datadog::CI::TestRetries::NullComponent do
  describe "#configure" do
    it "accepts the component configuration contract" do
      expect(subject.configure(double("library settings"), double("test session"))).to be_nil
    end
  end
end
