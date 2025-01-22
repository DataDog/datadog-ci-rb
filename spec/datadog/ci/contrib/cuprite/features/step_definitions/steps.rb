require "capybara"
require "capybara/cucumber"
require "capybara/cuprite"

Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(app, window_size: [1200, 800])
end

Capybara.current_driver = :cuprite
Capybara.default_driver = :cuprite
Capybara.javascript_driver = :cuprite

Then "visit page" do
  visit "http://www.example.com"

  Capybara.reset_session!

  Capybara.current_session.quit
end
