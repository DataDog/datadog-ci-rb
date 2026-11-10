# frozen_string_literal: true

module SharedDiscoveryTests
  def test_contract
    puts "EXECUTED_SHARED_CONTRACT"
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
    puts "EXECUTED_SHARED_NESTED"
    assert true
  end
end

class SharedDiscoveryBase < Minitest::Spec
  include SharedDiscoveryMethods
end
