# frozen_string_literal: true

# This consumer is in the ignored directory
class IgnoredConsumer
  def use_base
    Constants::BaseConstant.value
  end
end
