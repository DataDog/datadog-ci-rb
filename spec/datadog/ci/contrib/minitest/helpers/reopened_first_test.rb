# frozen_string_literal: true

require "minitest/spec"

class ReopenedDiscoverySpec < Minitest::Spec
  def test_from_first_file
    puts "EXECUTED_REOPENED_FIRST"
    assert true
  end
end
