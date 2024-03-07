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
  ],
  development: [
    "ruby-lsp",
    "ruby-lsp-rspec",
    "debug",
    "irb"
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

def self.with_ci_queue_minitest_gem(minitest_versions: 5, ci_queue_versions: 0)
  Array(minitest_versions).each do |minitest_v|
    Array(ci_queue_versions).each do |ci_queue_v|
      appraise "ci-queue-#{ci_queue_v}-minitest-#{minitest_v}" do
        gem "minitest", "~> #{minitest_v}"
        gem "ci-queue", "~> #{ci_queue_v}"
        gem "minitest-reporters", "~> 1"
      end
    end
  end
end

def self.with_ci_queue_rspec_gem(rspec_versions: 3, ci_queue_versions: 0)
  Array(rspec_versions).each do |rspec_v|
    Array(ci_queue_versions).each do |ci_queue_v|
      appraise "ci-queue-#{ci_queue_v}-rspec-#{rspec_v}" do
        gem "rspec", "~> #{rspec_v}"
        gem "ci-queue", "~> #{ci_queue_v}"
      end
    end
  end
end

def self.with_minitest_shoulda_context_gem(minitest_versions: 5, shoulda_context_versions: 2, shoulda_matchers_versions: 6)
  Array(minitest_versions).each do |minitest_v|
    Array(shoulda_context_versions).each do |shoulda_context_v|
      Array(shoulda_matchers_versions).each do |shoulda_matchers_v|
        appraise "minitest-#{minitest_v}-shoulda-context-#{shoulda_context_v}-shoulda-matchers-#{shoulda_matchers_v}" do
          gem "minitest", "~> #{minitest_v}"
          gem "shoulda-context", "~> #{shoulda_context_v}"
          gem "shoulda-matchers", "~> #{shoulda_matchers_v}"
        end
      end
    end
  end
end

ruby_version = Gem::Version.new(RUBY_ENGINE_VERSION)
major, minor, = ruby_version.segments

ruby_runtime = "#{RUBY_ENGINE}-#{major}.#{minor}"

with_minitest_gem
with_rspec_gem
with_cucumber_gem(versions: 3..9)
with_ci_queue_minitest_gem
with_ci_queue_rspec_gem
with_minitest_shoulda_context_gem if ruby_version >= Gem::Version.new("3.1")

appraisals.each do |appraisal|
  appraisal.name.prepend("#{ruby_runtime}-")
end

# vim: ft=ruby
