# frozen_string_literal: true

# This file doesn't reference any constants defined in the project
class NoDepsConsumer
  def compute(a, b)
    a + b
  end

  def greet(name)
    "Hello, #{name}!"
  end
end
