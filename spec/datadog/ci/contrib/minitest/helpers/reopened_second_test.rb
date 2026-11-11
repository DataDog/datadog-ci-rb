# frozen_string_literal: true

require "minitest/spec"

class ReopenedDiscoverySpec < Minitest::Spec
  def test_from_second_file
    puts "EXECUTED_REOPENED_SECOND"
    assert true
  end
end
