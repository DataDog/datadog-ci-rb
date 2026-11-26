# Loaded with Kernel#load by line_coverage_spec.rb: the spec asserts line numbers.
module LineCoverageNesting
  class << self
    def answer
      42
    end
  end

  begin
    Integer("not a number")
  rescue ArgumentError
    @parsed = false
  end

  def self.open_singleton(object)
    class << object
      def tag
        :tagged
      end
    end
    object.tag
  end

  def self.eval_class
    module_eval(<<~RUBY, __FILE__, __LINE__ + 1)
      class Evaluated
        def self.value
          7
        end
      end
    RUBY
    Evaluated.value
  end
end
