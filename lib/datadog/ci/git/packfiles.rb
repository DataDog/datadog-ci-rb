# frozen_string_literal: true

require "tmpdir"
require "fileutils"

require_relative "local_repository"

module Datadog
  module CI
    module Git
      module Packfiles
        def self.generate(included_commits:, excluded_commits:)
          # @type var current_process_tmp_folder: String?
          current_process_tmp_folder = nil

          Dir.mktmpdir do |tmpdir|
            prefix = LocalRepository.git_generate_packfiles(
              included_commits: included_commits,
              excluded_commits: excluded_commits,
              path: tmpdir
            )

            if prefix.nil?
              # git pack-files command fails if tmpdir is mounted on
              # a different device from the current process directory
              #
              # @type var current_process_tmp_folder: String
              current_process_tmp_folder = File.join(Dir.pwd, "tmp", "packfiles")
              FileUtils.mkdir_p(current_process_tmp_folder)

              prefix = LocalRepository.git_generate_packfiles(
                included_commits: included_commits,
                excluded_commits: excluded_commits,
                path: current_process_tmp_folder
              )

              if prefix.nil?
                Datadog.logger.debug("Packfiles generation failed twice, aborting")
                break
              end

              tmpdir = current_process_tmp_folder
            end

            packfiles = Dir.entries(tmpdir) - %w[. ..]
            if packfiles.empty?
              Datadog.logger.debug("Empty packfiles list, aborting process")
              break
            end

            packfiles.each do |packfile_name|
              next unless packfile_name.start_with?(prefix)
              next unless packfile_name.end_with?(".pack")

              packfile_path = File.join(tmpdir, packfile_name)

              yield packfile_path
            end
          end
        rescue => e
          Datadog.logger.debug("Packfiles could not be generated, error: #{e}")
        ensure
          FileUtils.remove_entry(current_process_tmp_folder) unless current_process_tmp_folder.nil?
        end
      end
    end
  end
end
