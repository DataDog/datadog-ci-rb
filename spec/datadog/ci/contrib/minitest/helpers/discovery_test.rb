# frozen_string_literal: true

require_relative "shared_discovery_tests"
require_relative "simple_model"

module MinitestDiscoveryFixtures
  describe "CustomerContract" do
    include SharedDiscoveryTests

    describe "nested context" do
      include SharedDiscoveryMethods
    end
  end

  describe SimpleModel do
    it("has an ordinary spec test") { assert true }
  end

  2.times do |index|
    describe "GeneratedContract#{index}" do
      include SharedDiscoveryMethods
    end
  end

  Class.new(Minitest::Spec) do
    include SharedDiscoveryMethods
  end

  class ClassContract < Minitest::Test
    include SharedDiscoveryMethods
  end

  class SpecContract < Minitest::Spec
    include SharedDiscoveryMethods
  end

  class InheritedContract < SharedDiscoveryBase
  end
end
