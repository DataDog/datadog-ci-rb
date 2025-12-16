# frozen_string_literal: true

# This file includes a module
class MixinConsumer
  include Constants::Mixable

  def use_mixin
    mixin_method
  end
end
