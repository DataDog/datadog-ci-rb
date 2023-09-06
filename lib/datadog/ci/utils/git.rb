module Datadog
  module CI
    module Utils
      module Git
        module_function

        def normalize_ref(name)
          return nil if name.nil?

          refs = %r{^refs/(heads/)?}
          origin = %r{^origin/}
          tags = %r{^tags/}
          name.gsub(refs, "").gsub(origin, "").gsub(tags, "")
        end

        def is_git_tag?(ref)
          !ref.nil? && ref.include?("tags/")
        end
      end
    end
  end
end
