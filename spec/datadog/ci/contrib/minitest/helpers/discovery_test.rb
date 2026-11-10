# frozen_string_literal: true

require_relative "shared_discovery_tests"
require_relative "simple_model"

module MinitestDiscoveryFixtures
  minitest_describe "CustomerContract" do
    include SharedDiscoveryTests

    minitest_describe "nested context" do
      include SharedDiscoveryMethods
    end
  end

  minitest_describe SimpleModel do
    it("has an ordinary spec test") { assert true }
  end

  2.times do |index|
    minitest_describe "GeneratedContract#{index}" do
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
