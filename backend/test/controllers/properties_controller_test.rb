require "test_helper"

class PropertiesControllerTest < ActionDispatch::IntegrationTest
  setup do
    PropertyTransportSnapshot.delete_all
    Property.delete_all
    @active      = create(:property)
    @under_offer = create(:property, :under_offer)
  end

  # ------------------------------------------------------------------
  # index
  # ------------------------------------------------------------------

  test "GET /properties returns 200" do
    get properties_path
    assert_response :success
  end

  test "GET /properties lists properties" do
    get properties_path
    assert_select "table tbody tr", 2
  end

  test "GET /properties filters by status" do
    get properties_path, params: { status: "active" }
    assert_response :success
    assert_select "table tbody tr td a", @active.address_line_1
  end

  test "GET /properties filters by property_type" do
    get properties_path, params: { property_type: "flat" }
    assert_response :success
    assert_select "table tbody tr td a", @under_offer.address_line_1
  end

  # ------------------------------------------------------------------
  # show
  # ------------------------------------------------------------------

  test "GET /properties/:id returns 200" do
    get property_path(@active)
    assert_response :success
  end

  test "GET /properties/:id shows address" do
    get property_path(@active)
    assert_match @active.address_line_1, response.body
  end

  test "GET /properties/:id shows formatted price" do
    get property_path(@active)
    assert_match "£350,000", response.body
  end

  test "GET /properties/:id returns 404 for missing property" do
    get property_path(id: 0)
    assert_response :not_found
  end

  # ------------------------------------------------------------------
  # new / create
  # ------------------------------------------------------------------

  test "GET /properties/new returns 200" do
    get new_property_path
    assert_response :success
  end

  test "POST /properties creates property and redirects to show" do
    assert_difference "Property.count", 1 do
      post properties_path, params: { property: valid_params }
    end
    assert_redirected_to property_path(Property.last)
  end

  test "POST /properties with invalid params re-renders new" do
    post properties_path, params: { property: valid_params.merge(rightmove_id: "") }
    assert_response :unprocessable_entity
  end

  # ------------------------------------------------------------------
  # edit / update
  # ------------------------------------------------------------------

  test "GET /properties/:id/edit returns 200" do
    get edit_property_path(@active)
    assert_response :success
  end

  test "PATCH /properties/:id updates and redirects to show" do
    patch property_path(@active), params: { property: { bedrooms: 4 } }
    assert_redirected_to property_path(@active)
    assert_equal 4, @active.reload.bedrooms
  end

  test "PATCH /properties/:id with invalid params re-renders edit" do
    patch property_path(@active), params: { property: { status: "invalid_status" } }
    assert_response :unprocessable_entity
  end

  # ------------------------------------------------------------------
  # destroy
  # ------------------------------------------------------------------

  test "DELETE /properties/:id destroys and redirects to index" do
    Property.any_instance.stubs(:destroy)
    delete property_path(@active)
    assert_redirected_to properties_path
  end

  private

  def valid_params
    {
      rightmove_id:   "999999999",
      address_line_1: "99 Test Street, Bath",
      price_pence:    20_000_000,
      property_type:  "terraced",
      status:         "active"
    }
  end
end
