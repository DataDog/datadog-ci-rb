lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

module DisableBundleCheck
  def check_command
    %w[bundle exec false]
  end
end

if %w[true y yes 1].include?(ENV["APPRAISAL_SKIP_BUNDLE_CHECK"])
  ::Appraisal::Appraisal.prepend(DisableBundleCheck)
end

alias original_appraise appraise

require "bundler"

definition = Bundler.definition
GEMS_TO_REMOVE = Hash.new { |hash, key| hash[key] = definition.dependencies_for([key]).map(&:name) }

[:development, :check].each { |g| GEMS_TO_REMOVE[g] }

RUBY_VERSION = Gem::Version.new(RUBY_ENGINE_VERSION)

def appraise(group, &block)
  # Specify the environment variable APPRAISAL_GROUP to load only a specific appraisal group.
  if ENV["APPRAISAL_GROUP"].nil? || ENV["APPRAISAL_GROUP"] == group
    original_appraise(group) do
      instance_exec(&block)

      GEMS_TO_REMOVE.each do |group_name, gems|
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
      if v == 9 && RUBY_ENGINE.include?("jruby")
        gem "bigdecimal", "< 3.1.8"
      end

      # ruby 3.4 extracts more parts of stdlib into gems
      if Gem::Version.new("3.4") <= RUBY_VERSION && !RUBY_ENGINE.include?("jruby") && (4..6).cover?(v)
        gem "base64"
        gem "mutex_m"
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
          if RUBY_ENGINE.include?("jruby")
            gem "bigdecimal", "< 3.1.8"
          end
        end
      end
    end
  end
end

def self.with_active_support_gem(versions: 7)
  Array(versions).each do |activesupport_v|
    appraise "activesupport-#{activesupport_v}" do
      gem "activesupport", "~> #{activesupport_v}"
      if RUBY_ENGINE.include?("jruby")
        gem "bigdecimal", "< 3.1.8"
      end
      # ruby 3.4 extracts more parts of stdlib into gems
      if Gem::Version.new("3.4") <= RUBY_VERSION && !RUBY_ENGINE.include?("jruby") && (4..6).cover?(activesupport_v)
        gem "base64"
        gem "mutex_m"
        gem "drb"
      end
    end
  end
end

def self.with_knapsack_pro_rspec_gem(knapsack_pro_versions: 7, rspec_versions: 3)
  Array(knapsack_pro_versions).each do |knapsack_pro_v|
    Array(rspec_versions).each do |rspec_v|
      appraise "knapsack_pro-#{knapsack_pro_v}-rspec-#{rspec_v}" do
        gem "knapsack_pro", "~> #{knapsack_pro_v}"
        gem "rspec", "~> #{rspec_v}"
      end
    end
  end
end

def self.with_selenium_gem(selenium_versions: 4, capybara_versions: 3)
  Array(selenium_versions).each do |selenium_v|
    Array(capybara_versions).each do |capybara_v|
      appraise "selenium-#{selenium_v}-capybara-#{capybara_v}" do
        gem "capybara", "~> #{capybara_v}"
        gem "selenium-webdriver", "~> #{selenium_v}"

        gem "cucumber", "~> 9"
      end
    end
  end
end

def self.with_timecop_gem(timecop_versions: 0)
  Array(timecop_versions).each do |timecop_v|
    appraise "timecop-#{timecop_v}" do
      gem "timecop", "~> #{timecop_v}"

      gem "minitest", "~> 5"
    end
  end
end

def self.with_cuprite_gem(cuprite_versions: 0, capybara_versions: 3)
  Array(cuprite_versions).each do |cuprite_v|
    Array(capybara_versions).each do |capybara_v|
      appraise "cuprite-#{cuprite_v}-capybara-#{capybara_v}" do
        gem "capybara", "~> #{capybara_v}"
        gem "cuprite", "~> #{cuprite_v}"

        gem "cucumber", "~> 9"
      end
    end
  end
end

major, minor, = RUBY_VERSION.segments

with_minitest_gem
with_rspec_gem
with_cucumber_gem(versions: 3..9)
with_ci_queue_minitest_gem
with_ci_queue_rspec_gem
with_minitest_shoulda_context_gem if Gem::Version.new("3.1") <= RUBY_VERSION
with_active_support_gem(versions: 4..7)
with_knapsack_pro_rspec_gem
with_selenium_gem if Gem::Version.new("3.0") <= RUBY_VERSION
with_timecop_gem
with_cuprite_gem if Gem::Version.new("3.0") <= RUBY_VERSION

ruby_runtime = "#{RUBY_ENGINE}-#{major}.#{minor}"

appraisals.each do |appraisal|
  appraisal.name.prepend("#{ruby_runtime}-")
end

# vim: ft=ruby
