# frozen_string_literal: true

module Datadog
  module CI
    module Contrib
      module Cucumber
        # instruments Cucumber::Core::Test::Step from cucumber-ruby-core to change
        module Step
          def self.included(base)
            base.prepend(InstanceMethods)
          end

          module InstanceMethods
            def execute(*args)
              test_span = CI.active_test
              if test_span&.skipped_by_itr?
                @action.skip(*args)
              else
                super
              end
            end
          end
        end
      end
    end
  end
end
