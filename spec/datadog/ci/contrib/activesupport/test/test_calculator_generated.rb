require "active_support"
require "minitest/spec"

require_relative "calculator"
require_relative "generator_helper"

class CalculatorGeneratedTest < ActiveSupport::TestCase
  include GeneratorHelper

  test_operations(:add, :subtract, :multiply, :divide)

  test "adds two numbers" do
    assert Calculator.new.add(1, 2) == 3
  end
end
