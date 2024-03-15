# frozen_string_literal: true

require_relative "operations/add"
require_relative "operations/divide"
require_relative "operations/multiply"
require_relative "operations/subtract"

class Calculator
  def initialize
    @adder = Add.new
    @subtractor = Subtract.new
    @multiplier = Multiply.new
    @divider = Divide.new
  end

  def add(a, b)
    @adder.call(a, b)
  end

  def subtract(a, b)
    @subtractor.call(a, b)
  end

  def multiply(a, b)
    @multiplier.call(a, b)
  end

  def divide(a, b)
    @divider.call(a, b)
  end
end
