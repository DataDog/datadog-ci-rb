# frozen_string_literal: true

require_relative "vendor/gems/operations/operations"

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
