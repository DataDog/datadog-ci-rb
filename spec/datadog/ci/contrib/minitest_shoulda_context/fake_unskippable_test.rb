require "shoulda-context"
require "shoulda-matchers"

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :minitest
  end
end

class Substractor
  def substract
    10 - 5
  end
end

class CalculatorUnskippable
  attr_reader :substractor

  def initialize
    @substractor = Substractor.new
  end

  def sum(a, b)
    a + b
  end

  def product(a, b)
    a * b
  end

  delegate :substract, to: :substractor
end

class CalculatorUnskippableTest < Minitest::Test
  datadog_itr_unskippable

  context "a calculator" do
    setup do
      @calculator = Calculator.new
    end

    should "add two numbers for the sum" do
      assert_equal 4, @calculator.sum(2, 2)
    end

    should "multiply two numbers for the product" do
      assert_equal 10, @calculator.product(2, 5)
    end

    should delegate_method(:substract).to(:substractor)
  end
end
