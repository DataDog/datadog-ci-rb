# frozen_string_literal: true

# This file uses fully qualified constant names (opt_getconstant_path instruction)
class FullyQualifiedConsumer
  def use_base
    Constants::BaseConstant.value
  end

  def use_nested
    Constants::Nested::DeeplyNestedConstant.value
  end

  def use_another
    Constants::AnotherConstant.value
  end
end
