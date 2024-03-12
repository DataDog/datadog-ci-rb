module DivideHelper
  extend ActiveSupport::Concern

  class_methods do
    def should_divide(&block)
      test "should divide" do
        instance = instance_eval(&block)

        assert instance.divide(4, 2) == 2
      end
    end
  end
end
