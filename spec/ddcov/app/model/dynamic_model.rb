# frozen_string_literal: true

class DynamicModel
  def method_missing(name, *args)
    "called #{name} with #{args}"
  end

  def respond_to_missing?(name, include_private = false)
    true
  end
end
