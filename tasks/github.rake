require 'json'
require_relative 'appraisal_conversion'

namespace :github do
  task :generate_matrix do
    matrix = TEST_METADATA

    ruby_version = RUBY_VERSION[0..2]
    array = []
    matrix.each do |key, spec_metadata|
      spec_metadata.each do |group, rubies|
        matched = if RUBY_PLATFORM == 'java'
          rubies.include?("✅ #{ruby_version}") && rubies.include?('✅ jruby')
        else
          rubies.include?("✅ #{ruby_version}")
        end

        if matched
          gemfile = AppraisalConversion.to_bundle_gemfile(group) rescue "Gemfile"

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
