# frozen_string_literal: true

# This file uses both qualified and unqualified constant names
class MixedConsumer
  def use_fully_qualified
    Constants::BaseConstant.value
  end

  def use_standalone
    StandaloneClass.value
  end

  def use_root_qualified
    # Top-level constant access via ::
    ::StandaloneClass.value
  end
end
