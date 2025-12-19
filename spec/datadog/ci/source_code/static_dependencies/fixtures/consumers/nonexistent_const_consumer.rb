# frozen_string_literal: true

# This file references a constant that doesn't exist
# The const_source_location call will return nil or raise for this
class NonexistentConstConsumer
  def try_to_use
    # This method body references NonExistentModule::NonExistentClass
    # but it's wrapped in a rescue to prevent runtime errors

    NonExistentModule::NonExistentClass.new
  rescue NameError
    nil
  end
end
