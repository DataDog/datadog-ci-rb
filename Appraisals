lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

module DisableBundleCheck
  def check_command
    ["bundle", "exec", "false"]
  end
end

if ["true", "y", "yes", "1"].include?(ENV["APPRAISAL_SKIP_BUNDLE_CHECK"])
  ::Appraisal::Appraisal.prepend(DisableBundleCheck)
end

alias original_appraise appraise

REMOVED_GEMS = {
  check: [
    "rbs",
    "steep"
  ]
}

def appraise(group, &block)
  # Specify the environment variable APPRAISAL_GROUP to load only a specific appraisal group.
  if ENV["APPRAISAL_GROUP"].nil? || ENV["APPRAISAL_GROUP"] == group
    original_appraise(group) do
      instance_exec(&block)

      REMOVED_GEMS.each do |group_name, gems|
        group(group_name) do
          gems.each do |gem_name|
            remove_gem gem_name
          end
        end
      end
    end
  end
end

def self.with_rspec_gem(versions: 3)
  Array(versions).each do |v|
    appraise "rspec-#{v}" do
      gem "rspec", "~> #{v}"
    end
  end
end

def self.with_cucumber_gem(versions:)
  Array(versions).each do |v|
    appraise "cucumber-#{v}" do
      gem "cucumber", "~> #{v}"
      # cucumber versions 4-6 are not compatible with activesupport 7.1
      if (4..6).cover?(v)
        gem "activesupport", "< 7.1"
      end
    end
  end
end

def self.with_minitest_gem(versions: 5)
  Array(versions).each do |v|
    appraise "minitest-#{v}" do
      gem "minitest", "~> #{v}"
    end
  end
end

with_minitest_gem
with_rspec_gem
with_cucumber_gem(versions: 3..8)

ruby_runtime = "#{RUBY_ENGINE}-#{RUBY_ENGINE_VERSION}"

appraisals.each do |appraisal|
  appraisal.name.prepend("#{ruby_runtime}-")
end

# vim: ft=ruby
