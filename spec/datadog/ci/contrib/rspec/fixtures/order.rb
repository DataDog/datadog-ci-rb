# frozen_string_literal: true

# Helper class for testing context coverage feature.
# Called in before(:context) hooks to verify that code coverage
# is properly collected during context setup.

module ContextCoverageHelper
  class Order
    attr_reader :items

    def initialize
      @items = []
    end

    def add_item(item)
      @items << item
    end

    def total
      @items.sum
    end
  end
end
