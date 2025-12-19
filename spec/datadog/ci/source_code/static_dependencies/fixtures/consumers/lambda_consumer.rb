# frozen_string_literal: true

# This file references constants inside lambdas and blocks
class LambdaConsumer
  def self.lazy_loader
    -> { Constants::BaseConstant.value }
  end

  def self.block_executor
    # Use tap block to reference constants in block context
    [].tap do |arr|
      arr << Constants::AnotherConstant.value
    end.first
  end

  def self.proc_creator
    proc { StandaloneClass.value }
  end
end
