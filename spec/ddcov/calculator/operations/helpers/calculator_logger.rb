# frozen_string_literal: true

module CalculatorLogger
  def call(a, b)
    res = super

    @log ||= []
    @log << "operation performed"

    res
  end
end
