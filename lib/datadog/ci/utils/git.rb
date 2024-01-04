# frozen_string_literal: true

require "open3"

module Datadog
  module CI
    module Utils
      module Git
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

        def self.exec_git_command(cmd)
          out, status = Open3.capture2e(cmd)

          raise "Failed to run git command #{cmd}: #{out}" unless status.success?

          # Sometimes Encoding.default_external is somehow set to US-ASCII which breaks
          # commit messages with UTF-8 characters like emojis
          # We force output's encoding to be UTF-8 in this case
          # This is safe to do as UTF-8 is compatible with US-ASCII
          if Encoding.default_external == Encoding::US_ASCII
            out = out.force_encoding(Encoding::UTF_8)
          end
          out.strip! # There's always a "\n" at the end of the command output

          return nil if out.empty?

          out
        end
      end
    end
  end
end
