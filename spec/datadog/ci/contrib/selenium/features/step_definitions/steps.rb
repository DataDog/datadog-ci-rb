require "capybara"
require "capybara/cucumber"

Capybara.default_driver = :selenium_headless

Then "visit page" do
  visit "http://www.example.com"
  Capybara.current_session.quit
rescue => e
  p e.backtrace
end
