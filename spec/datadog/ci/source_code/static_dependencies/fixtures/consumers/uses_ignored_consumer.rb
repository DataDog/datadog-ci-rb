# frozen_string_literal: true

# This file references a constant from the ignored directory
class UsesIgnoredConsumer
  def use_ignored
    IgnoredConstant.value
  end
end
