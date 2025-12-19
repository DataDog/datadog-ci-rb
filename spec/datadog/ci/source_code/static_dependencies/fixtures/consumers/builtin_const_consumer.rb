# frozen_string_literal: true

# This file references built-in Ruby constants that have no source location
class BuiltinConstConsumer
  def use_builtins
    # References to core Ruby constants - these have no source location
    s = +"hello"
    a = Array.new(3)
    h = Hash.new(0)
    n = Integer(42)
    [s, a, h, n]
  end

  def use_stdlib
    # Reference constants from stdlib - these are typically defined in C
    [File.dirname(__FILE__), Dir.pwd]
  end
end
