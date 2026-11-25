# Loaded with Kernel#load by line_coverage_spec.rb: the spec asserts line numbers.
module LineCoverageGeometry
  class Square
    def initialize(side)
      @side = side
    end

    def area
      @side * @side
    end

    def describe(size)
      if size == :long
        "a square with side #{@side}"
      else
        "square"
      end
    end
  end

  def self.setup_value
    41 + 1
  end

  def self.in_thread
    Thread.new do
      2 * 21
    end.value
  end

  def self.teardown_value
    :done
  end
end
