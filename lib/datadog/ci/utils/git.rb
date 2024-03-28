# frozen_string_literal: true

require "open3"
require "pathname"

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

        def self.root
          return @root if defined?(@root)

          @root = exec_git_command("git rev-parse --show-toplevel") || Dir.pwd
        rescue => e
          Datadog.logger.debug(
            "Unable to read git root: #{e.class.name} #{e.message} at #{Array(e.backtrace).first}"
          )
          @root = Dir.pwd
        end

        def self.relative_to_root(path)
          return "" if path.nil?

          git_root = root
          return path if git_root.nil?

          path = Pathname.new(File.expand_path(path))
          git_root = Pathname.new(git_root)

          path.relative_path_from(git_root).to_s
        end

        def self.repository_name
          return @repository_name if defined?(@repository_name)

          git_remote_url = exec_git_command("git ls-remote --get-url origin")

          # return git repository name from remote url without .git extension
          last_path_segment = git_remote_url.split("/").last if git_remote_url
          @repository_name = last_path_segment.gsub(".git", "") if last_path_segment
          @repository_name ||= current_folder_name
        rescue => e
          Datadog.logger.debug(
            "Unable to get git remote: #{e.class.name} #{e.message} at #{Array(e.backtrace).first}"
          )
          @repository_name = current_folder_name
        end

        def self.current_folder_name
          root_folder = root
          if root_folder.nil?
            File.basename(Dir.pwd)
          else
            File.basename(root_folder)
          end
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
