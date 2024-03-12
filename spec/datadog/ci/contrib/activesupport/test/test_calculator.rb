require "active_support"
require "minitest/spec"

require_relative "calculator"
require_relative "divide_helper"

class CalculatorTest < ActiveSupport::TestCase
  include DivideHelper

  test "adds two numbers" do
    assert Calculator.new.add(1, 2) == 3
  end

  test "subtracts two numbers" do
    assert Calculator.new.subtract(2, 1) == 1
  end

  should_divide { Calculator.new }
end
