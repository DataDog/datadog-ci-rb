lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
# require 'ddtrace/version'

module DisableBundleCheck
  def check_command
    ["bundle", "exec", "false"]
  end
end

if ["true", "y", "yes", "1"].include?(ENV["APPRAISAL_SKIP_BUNDLE_CHECK"])
  ::Appraisal::Appraisal.prepend(DisableBundleCheck)
end

def ruby_version?(version)
  full_version = "#{version}.0" # Turn 2.1 into 2.1.0 otherwise #bump below doesn't work as expected

  Gem::Version.new(full_version) <= Gem::Version.new(RUBY_VERSION) &&
    Gem::Version.new(RUBY_VERSION) < Gem::Version.new(full_version).bump
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
            # appraisal 2.2 doesn't have remove_gem, which applies to ruby 2.1 and 2.2
            remove_gem gem_name if respond_to?(:remove_gem)
          end
        end
      end
    end
  end
end

# def self.with_cucumber_gem(version)
#   appraise "cucumber#{version}" do
#     gem "cucumber", "~>#{version}"
#     # Locks the profiler's protobuf dependency to avoid conflict with cucumber.
#     # Without this, we can get this error:
#     # > TypeError:
#     # >   superclass mismatch for class FileDescriptorSet
#     # This happens because cucumber has its own Protobuf gem (`protobuf-cucumber`)
#     # that conflicts with `google-protobuf`: the load slightly different version of the same classes.
#     # Locking them together ensures they don't have conflicting class declaration.
#     # This only affects: 4.0.0 >= cucumber > 7.0.0.
#     #
#     # DEV: Ideally, the profiler would not be loaded when running cucumber tests as it is unrelated.
#     if Gem::Version.new(version) >= Gem::Version.new("4.0.0") &&
#         Gem::Version.new(version) < Gem::Version.new("7.0.0")
#       gem "google-protobuf", "3.10.1" if RUBY_PLATFORM != "java"
#       gem "protobuf-cucumber", "3.10.8"
#     end
#   end
# end

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
    end
  end
end

# WIP: Support cucumber 8

# | Cucumber | Ruby required |
# |----------|---------------|
# | 3.x      |   2.2+        |
# | 4.x      |   2.3+        |
# | 5.x      |   2.5+        |
# | 6.x      |   2.5+        |
# | 7.x      |   2.5+        |
# | 8.x      |   2.6+        |
if ruby_version?("2.1")
  with_rspec_gem
elsif ruby_version?("2.2")
  with_rspec_gem
  with_cucumber_gem(versions: 3)
elsif ruby_version?("2.3")
  with_rspec_gem
  with_cucumber_gem(versions: 3..4)
elsif ruby_version?("2.4")
  with_rspec_gem
  with_cucumber_gem(versions: 3..4)
elsif ruby_version?("2.5")
  with_rspec_gem
  with_cucumber_gem(versions: 3..7)
elsif ruby_version?("2.6")
  with_rspec_gem
  with_cucumber_gem(versions: 3..7)
elsif ruby_version?("2.7")
  with_rspec_gem
  with_cucumber_gem(versions: 3..7)
elsif ruby_version?("3.0")
  with_rspec_gem
  with_cucumber_gem(versions: 3..7)
elsif ruby_version?("3.1")
  with_rspec_gem
  with_cucumber_gem(versions: 3..7)
elsif ruby_version?("3.2")
  with_rspec_gem
  with_cucumber_gem(versions: 3..7)
end

ruby_runtime = if defined?(RUBY_ENGINE_VERSION)
  "#{RUBY_ENGINE}-#{RUBY_ENGINE_VERSION}"
else
  "#{RUBY_ENGINE}-#{RUBY_VERSION}" # For Ruby < 2.3
end

appraisals.each do |appraisal|
  appraisal.name.prepend("#{ruby_runtime}-")
end

# vim: ft=ruby