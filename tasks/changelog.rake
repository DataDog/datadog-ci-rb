namespace :changelog do
  task :format do
    require "pimpmychangelog"

    PimpMyChangelog::CLI.run!
  end
end
