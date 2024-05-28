require "capybara"
require "capybara/cucumber"

Capybara.default_driver = :selenium_headless

Then "visit page" do
  visit "http://www.example.com"

  Capybara.reset_session!

  Capybara.current_session.quit
end
