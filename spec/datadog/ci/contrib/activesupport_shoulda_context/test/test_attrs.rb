# frozen_string_literal: true

require "shoulda-context"
require "shoulda-matchers"

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :minitest
  end
end

module TestAttrs
  extend ActiveSupport::Concern

  included do |base|
    should delegate_method(:a).to(:b)
  end

  class_methods do
    def test_attrs(*paths, attributes: {})
      paths.each do |path|
        test "check attr at #{path}" do
          assert_attr(path, attributes)
        end
      end
    end

    alias_method :test_attr, :test_attrs
  end

  def assert_attr(path, attributes = {})
    # noop
  end
end
