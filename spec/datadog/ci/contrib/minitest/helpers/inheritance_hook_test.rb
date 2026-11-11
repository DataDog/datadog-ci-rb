# frozen_string_literal: true

require_relative "inheritance_hook_base"
require_relative "discovery_execution"

module InheritanceHookDiscoveryTests
  def test_local_contract
    MinitestDiscoveryFixtures::EXECUTED_TESTS << name
    assert_includes InheritanceHookDiscoveryBase.registered_subclasses, self.class
  end
end

class InheritanceHookDiscoverySpec < InheritanceHookDiscoveryBase
  include InheritanceHookDiscoveryTests
end
