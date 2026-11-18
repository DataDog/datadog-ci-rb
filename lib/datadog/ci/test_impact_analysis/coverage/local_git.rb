# frozen_string_literal: true

require "open3"
require_relative "../../utils/git"

module Datadog
  module CI
    module TestImpactAnalysis
      module Coverage
        class LocalGit
          def initialize(root)
            @root = root
          end

          def head
            value = command("rev-parse", "HEAD").strip
            raise ArgumentError, "invalid Git HEAD" unless Utils::Git.valid_commit_sha?(value)
            value
          end

          def changed_files(base_commit)
            raise ArgumentError, "invalid baseline commit" unless Utils::Git.valid_commit_sha?(base_commit)
            command("cat-file", "-e", "#{base_commit}^{commit}")
            tracked = command("diff", "--no-ext-diff", "--no-textconv", "--no-renames", "--name-only", "-z", base_commit, "--")
            untracked = command("ls-files", "--others", "--exclude-standard", "-z")
            (tracked.split("\0") + untracked.split("\0")).uniq
          end

          private

          def command(*arguments)
            output, error, status = Open3.capture3("git", "--no-optional-locks", "-C", @root, *arguments)
            raise "Local TIA Git command failed: #{error.strip}" unless status.success?
            output
          end
        end
      end
    end
  end
end
