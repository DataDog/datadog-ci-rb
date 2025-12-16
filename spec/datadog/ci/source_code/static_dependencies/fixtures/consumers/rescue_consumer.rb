# frozen_string_literal: true

# This file references constants in rescue/ensure blocks
class RescueConsumer
  def self.with_rescue
    Constants::BaseConstant.value
  rescue
    Constants::AnotherConstant.value
  ensure
    StandaloneClass.value
  end

  def self.inline_rescue
    Constants::BaseConstant.value
  rescue
    nil
  end
end
