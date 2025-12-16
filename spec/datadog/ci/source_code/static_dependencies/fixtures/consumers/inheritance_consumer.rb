# frozen_string_literal: true

# This file uses inheritance pattern
class InheritanceConsumer < Constants::BaseConstant
  def self.extended_value
    "#{value}_extended"
  end
end
