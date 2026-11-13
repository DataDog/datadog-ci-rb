# frozen_string_literal: true

require "minitest/spec"
require_relative "discovery_execution"

class ReopenedDiscoverySpec < Minitest::Spec
  def test_from_first_file
    MinitestDiscoveryFixtures::EXECUTED_TESTS << name
    assert true
  end
end
