require "test_helper"

module Api
  module V1
    class PropertiesControllerTest < ActionDispatch::IntegrationTest
      setup do
        Property.delete_all
        @active      = create(:property)
        @under_offer = create(:property, :under_offer)
      end

      # ------------------------------------------------------------------
      # index
      # ------------------------------------------------------------------

      test "GET /api/v1/properties returns 200 with JSON" do
        get api_v1_properties_path, as: :json
        assert_response :success
        assert_equal "application/json", response.media_type
      end

      test "GET /api/v1/properties returns properties array and total" do
        get api_v1_properties_path, as: :json
        body = response.parsed_body
        assert body.key?("properties")
        assert_equal 2, body["total"]
      end

      test "GET /api/v1/properties filters by status" do
        get api_v1_properties_path, params: { status: "active" }, as: :json
        ids = response.parsed_body["properties"].map { |p| p["rightmove_id"] }
        assert_includes ids, @active.rightmove_id
        assert_not_includes ids, @under_offer.rightmove_id
      end

      test "GET /api/v1/properties filters by property_type" do
        get api_v1_properties_path, params: { property_type: "flat" }, as: :json
        ids = response.parsed_body["properties"].map { |p| p["rightmove_id"] }
        assert_includes ids, @under_offer.rightmove_id
        assert_not_includes ids, @active.rightmove_id
      end

      test "GET /api/v1/properties filters by min_price" do
        get api_v1_properties_path, params: { min_price: 30_000_000 }, as: :json
        ids = response.parsed_body["properties"].map { |p| p["rightmove_id"] }
        assert_includes ids, @active.rightmove_id
        assert_not_includes ids, @under_offer.rightmove_id
      end

      test "GET /api/v1/properties filters by max_price" do
        get api_v1_properties_path, params: { max_price: 30_000_000 }, as: :json
        ids = response.parsed_body["properties"].map { |p| p["rightmove_id"] }
        assert_includes ids, @under_offer.rightmove_id
        assert_not_includes ids, @active.rightmove_id
      end

      # ------------------------------------------------------------------
      # show
      # ------------------------------------------------------------------

      test "GET /api/v1/properties/:id returns property" do
        get api_v1_property_path(@active), as: :json
        assert_response :success
        assert_equal @active.rightmove_id, response.parsed_body["rightmove_id"]
      end

      test "GET /api/v1/properties/:id excludes raw_data" do
        get api_v1_property_path(@active), as: :json
        assert_not response.parsed_body.key?("raw_data")
      end

      test "GET /api/v1/properties/:id returns 404 for missing property" do
        get api_v1_property_path(id: 0), as: :json
        assert_response :not_found
        assert_equal "Not found", response.parsed_body["error"]
      end

      # ------------------------------------------------------------------
      # create
      # ------------------------------------------------------------------

      test "POST /api/v1/properties creates and returns 201" do
        assert_difference "Property.count", 1 do
          post api_v1_properties_path, params: { property: valid_params }, as: :json
        end
        assert_response :created
        assert_equal "999888777", response.parsed_body["rightmove_id"]
      end

      test "POST /api/v1/properties returns errors on invalid params" do
        post api_v1_properties_path,
             params: { property: valid_params.merge(rightmove_id: "") }, as: :json
        assert_response :unprocessable_entity
        assert response.parsed_body["errors"].any?
      end

      # ------------------------------------------------------------------
      # update
      # ------------------------------------------------------------------

      test "PATCH /api/v1/properties/:id updates and returns property" do
        patch api_v1_property_path(@active),
              params: { property: { bedrooms: 5 } }, as: :json
        assert_response :success
        assert_equal 5, response.parsed_body["bedrooms"]
        assert_equal 5, @active.reload.bedrooms
      end

      test "PATCH /api/v1/properties/:id returns errors on invalid params" do
        patch api_v1_property_path(@active),
              params: { property: { status: "invalid" } }, as: :json
        assert_response :unprocessable_entity
        assert response.parsed_body["errors"].any?
      end

      # ------------------------------------------------------------------
      # destroy
      # ------------------------------------------------------------------

      test "DELETE /api/v1/properties/:id destroys and returns 204" do
        Property.any_instance.stubs(:destroy!)
        delete api_v1_property_path(@active), as: :json
        assert_response :no_content
      end

      private

      def valid_params
        {
          rightmove_id:   "999888777",
          address_line_1: "99 API Street, Bath",
          price_pence:    20_000_000,
          property_type:  "terraced",
          status:         "active"
        }
      end
    end
  end
end
