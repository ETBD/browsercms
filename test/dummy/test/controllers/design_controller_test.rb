require "test_helper"

class DesignControllerTest < ActionController::TestCase
  # DesignController#show renders the template named by params[:page], and the
  # route (/design/:page) always supplies one. Calling it bare rendered nil,
  # which fell through to a design/show template that has never existed.
  test "should get show" do
    get :show, params: {page: "dashboard"}
    assert_response :success
  end

end
