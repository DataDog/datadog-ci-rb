require_relative "constants"

module AdditionHelper
  def self.add(a, b)
    a + b
  end

  def self.symbol
    Operations::PLUS
  end
end
