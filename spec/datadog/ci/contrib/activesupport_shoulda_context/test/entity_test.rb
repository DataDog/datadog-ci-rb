# frozen_string_literal: true

require "active_support"
require "minitest/spec"

require_relative "test_attrs"
# minitest adds `describe` method to Kernel, which conflicts with RSpec.
# here we define `minitest_describe` method to avoid this conflict.
module Kernel
  alias_method :minitest_describe, :describe
end

class B
  def a
    "a"
  end
end

class Entity
  attr_reader :b

  delegate :a, to: :b

  def initialize
    @b = B.new
  end
end

class EntityTest < ActiveSupport::TestCase
  def self.test_order
    :random
  end

  extend Minitest::Spec::DSL

  include TestAttrs

  test "something" do
  end

  minitest_describe "attrs" do
    test_attr("/a", "/b", "/c", "/d")
    test_attrs("/e", "/g", attributes: {data: []})
  end
end
