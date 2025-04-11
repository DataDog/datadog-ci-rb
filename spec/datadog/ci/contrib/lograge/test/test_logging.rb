require "active_support"
require "action_dispatch/testing/integration"

class LoggingTest < ActionDispatch::IntegrationTest
  test "gets logging" do
    get "/logging"
    assert_response :success
  end
end
