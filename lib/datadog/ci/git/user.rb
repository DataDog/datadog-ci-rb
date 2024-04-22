# frozen_string_literal: true

module Datadog
  module CI
    module Git
      class User
        attr_reader :name, :email, :timestamp

        def initialize(name, email, timestamp)
          @name = name
          @email = email
          @timestamp = timestamp
        end

        def date
          return nil if timestamp.nil?

          Time.at(timestamp.to_i).utc.to_datetime.iso8601
        end
      end

      class NilUser < User
        def initialize
          super(nil, nil, nil)
        end
      end
    end
  end
end
