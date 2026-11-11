# frozen_string_literal: true

require "minitest/spec"

class InheritanceHookDiscoveryBase < Minitest::Spec
  def self.registered_subclasses
    @registered_subclasses ||= []
  end

  def self.inherited(subclass)
    registered_subclasses << subclass
    super
  end
end
