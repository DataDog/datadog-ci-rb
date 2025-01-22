require "capybara"
require "capybara/cucumber"

Capybara.default_driver = :selenium_headless

Then "visit page" do
  visit "http://www.example.com"
  p "visited"

  Capybara.reset_session!
  p "reset"

  Capybara.current_session.quit
  p "quit"
end
