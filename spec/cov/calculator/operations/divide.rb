# frozen_string_literal: true

require_relative "helpers/calculator_logger"

class Divide
  prepend CalculatorLogger

  def call(a, b)
    a / b
  end
end
