# frozen_string_literal: true

require "open3"
require "pathname"

module Datadog
  module CI
    module Utils
      module Git
        def self.valid_commit_sha?(sha)
          return false if sha.nil?

          sha.match?(/\A[0-9a-f]{40}\Z/) || sha.match?(/\A[0-9a-f]{64}\Z/)
        end

        def self.normalize_ref(ref)
          return nil if ref.nil?

          refs = %r{^refs/(heads/)?}
          origin = %r{^origin/}
          tags = %r{^tags/}
          ref.gsub(refs, "").gsub(origin, "").gsub(tags, "")
        end

        def self.is_git_tag?(ref)
          !ref.nil? && ref.include?("tags/")
        end
      end
    end
  end
end
