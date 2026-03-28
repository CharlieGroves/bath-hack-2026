require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  setup do
    PropertyTransportSnapshot.delete_all
    Property.delete_all
    @active      = create(:property)
    @under_offer = create(:property, :under_offer)
  end

  test "GET / returns 200" do
    get root_path
    assert_response :success
  end

  test "GET / shows total property count" do
    get root_path
    assert_match "2", response.body
  end

  test "GET / shows active listing count" do
    get root_path
    assert_match "1", response.body
  end

  test "GET / links to properties index" do
    get root_path
    assert_select "a[href=?]", properties_path
  end
end
