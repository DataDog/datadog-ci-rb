# frozen_string_literal: true

# This file uses unqualified constant names (getconstant instruction)
# by opening the module namespace first
module Constants
  class UnqualifiedConsumer
    def use_base
      BaseConstant.value
    end

    def use_another
      AnotherConstant.value
    end
  end
end
