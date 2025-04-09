module GeneratorHelper
  extend ActiveSupport::Concern

  class_methods do
    def test_operations(*operations)
      operations.each do |operation|
        test "performs #{operation}" do
          assert Calculator.new.public_send(operation, 1, 2)
        end
      end
    end
  end
end
