# frozen_string_literal: true

# This file references multiple constants from the project
class MultiDepsConsumer
  def use_all
    [
      Constants::BaseConstant.value,
      Constants::AnotherConstant.value,
      Constants::Nested::DeeplyNestedConstant.value,
      StandaloneClass.value
    ].join(", ")
  end
end
