# frozen_string_literal: true

namespace :lint do
  desc "Check Datadog environment variable prefixes"
  task :env do
    ruby "scripts/lint_env.rb"
  end
end
