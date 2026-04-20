require "json"
require_relative "appraisal_conversion"

namespace :github do
  task :generate_matrix do
    matrix = TEST_METADATA

    ruby_version = RUBY_VERSION[0..2]
    array = []
    matrix.each do |key, spec_metadata|
      spec_metadata.each do |group, rubies|
        matched = rubies.include?("✅ #{ruby_version}")

        if matched
          gemfile = begin
            AppraisalConversion.to_bundle_gemfile(group)
          rescue
            "Gemfile"
          end

          array << {
            group: group,
            gemfile: gemfile,
            task: key
          }
        end
      end
    end

    puts JSON.dump(array)
  end
end
