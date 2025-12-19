# frozen_string_literal: true

# This file assigns constants to local variables
class ConstantAssignmentConsumer
  def use_via_variable
    klass = Constants::BaseConstant
    klass.value
  end

  def use_multiple_via_variables
    a = Constants::BaseConstant
    b = Constants::AnotherConstant
    c = StandaloneClass
    [a.value, b.value, c.value]
  end
end
