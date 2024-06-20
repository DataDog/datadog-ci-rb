# frozen_string_literal: true

require "rake"

module Datadog
  module CI
    module Tasks
      class << self
        include Rake::DSL

        def load!
          path = File.expand_path(File.join(File.dirname(__FILE__), "../../tasks/**/*.rake"))
          Dir.glob(path).each { |r| import(r) }
        end
      end
    end
  end
end

Datadog::CI::Tasks.load!
