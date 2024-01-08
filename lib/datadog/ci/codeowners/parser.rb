# frozen_string_literal: true

require_relative "matcher"

module Datadog
  module CI
    module Codeowners
      # Responsible for parsing a CODEOWNERS file
      class Parser
        DEFAULT_LOCATION = "CODEOWNERS"
        POSSIBLE_CODEOWNERS_LOCATIONS = [
          "CODEOWNERS",
          ".github/CODEOWNERS",
          ".gitlab/CODEOWNERS",
          "docs/CODEOWNERS"
        ].freeze

        def initialize(root_file_path)
          @root_file_path = root_file_path || Dir.pwd
        end

        def parse
          default_path = File.join(@root_file_path, DEFAULT_LOCATION)
          # We are using the first codeowners file that we find or
          # default location if nothing is found
          #
          # Matcher handles it internally and creates a class with
          # an empty list of rules if the file is not found
          codeowners_file_path = POSSIBLE_CODEOWNERS_LOCATIONS.map do |codeowners_location|
            File.join(@root_file_path, codeowners_location)
          end.find do |path|
            File.exist?(path)
          end || default_path

          Matcher.new(codeowners_file_path)
        end
      end
    end
  end
end
