# frozen_string_literal: true

require_relative "discovery_execution"

module SharedDiscoveryTests
  def test_contract
    MinitestDiscoveryFixtures::EXECUTED_TESTS << name
    assert_equal 2, 1 + 1
  end

  def self.included(base)
    base.class_eval do
      describe "shared nested context" do
        include SharedDiscoveryMethods
      end
    end
  end
end

module SharedDiscoveryMethods
  def test_shared_nested
    MinitestDiscoveryFixtures::EXECUTED_TESTS << name
    assert true
  end
end

class SharedDiscoveryBase < Minitest::Spec
  include SharedDiscoveryMethods
end
