# frozen_string_literal: true

# This file references constants inside conditionals
class ConditionalConsumer
  def self.conditional_use(flag)
    if flag
      Constants::BaseConstant.value
    else
      Constants::AnotherConstant.value
    end
  end

  def self.case_use(choice)
    case choice
    when :base
      Constants::BaseConstant.value
    when :nested
      Constants::Nested::DeeplyNestedConstant.value
    else
      StandaloneClass.value
    end
  end

  def self.ternary_use(flag)
    flag ? Constants::BaseConstant.value : Constants::AnotherConstant.value
  end
end
