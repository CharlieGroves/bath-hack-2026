require "test_helper"

module Api
  module V1
    class PropertiesControllerTest < ActionDispatch::IntegrationTest
      setup do
        PropertyTransportSnapshot.delete_all
        Property.delete_all
        @active      = create(:property)
        @under_offer = create(:property, :under_offer)
        @active.create_property_transport_snapshot!(
          provider: "england_noise_data",
          latitude: @active.latitude || 51.3812,
          longitude: @active.longitude || -0.1534,
          fetched_at: Time.current,
          status: "ready",
          flight_data: { "covered" => true, "metrics" => { "lden" => 64.4, "laeq16hr" => 60.5 } },
          rail_data: { "covered" => true, "metrics" => { "lden" => 55.8, "laeq16hr" => 52.7 } },
          road_data: { "covered" => true, "metrics" => { "lden" => 62.1, "laeq16hr" => 58.4 } }
        )
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
        assert_equal 64.4, body["properties"].find { |property| property["id"] == @active.id }["noise"]["flight_data"]["metrics"]["lden"]
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

      test "GET /api/v1/properties/search returns the isochrone geometry and matching properties" do
        inside = create(:property, rightmove_id: "300200100", latitude: 51.3810, longitude: -2.3610)
        create(:property, rightmove_id: "300200101", latitude: 51.3890, longitude: -2.3490)

        NominatimGeocoder.any_instance.stubs(:search!).with("Bath Abbey").returns(
          { latitude: 51.3811, longitude: -2.3590, label: "Bath Abbey, Bath, UK" }
        )
        TravelTimeGateway.any_instance.stubs(:isochrone!).returns(
          {
            bounding_box: { north: 51.39, south: 51.37, east: -2.35, west: -2.37 },
            shells: [
              [
                { latitude: 51.37, longitude: -2.37 },
                { latitude: 51.37, longitude: -2.35 },
                { latitude: 51.385, longitude: -2.36 }
              ]
            ]
          }
        )

        get search_api_v1_properties_path,
            params: { query: "Bath Abbey", travel_time_minutes: 10, transportation_type: "walking" },
            as: :json

        assert_response :success
        assert_equal "Bath Abbey", response.parsed_body["query"]
        assert_equal "Bath Abbey, Bath, UK", response.parsed_body["location"]["label"]
        assert_equal 600, response.parsed_body["travel_time_seconds"]
        assert_equal 51.39, response.parsed_body["bounding_box"]["north"]
        assert_equal 1, response.parsed_body["isochrone_shells"].length
        assert_equal [inside.rightmove_id], response.parsed_body["properties"].map { |property| property["rightmove_id"] }
      end

      test "GET /api/v1/properties/search returns 404 when the location cannot be found" do
        NominatimGeocoder.any_instance.stubs(:search!).raises(
          NominatimGeocoder::LocationNotFound,
          'No location found for "Atlantis"'
        )

        get search_api_v1_properties_path, params: { query: "Atlantis" }, as: :json

        assert_response :not_found
        assert_equal 'No location found for "Atlantis"', response.parsed_body["error"]
      end

      test "GET /api/v1/properties/search returns 503 when TravelTime is not configured" do
        NominatimGeocoder.any_instance.stubs(:search!).returns(
          { latitude: 51.3811, longitude: -2.3590, label: "Bath Abbey, Bath, UK" }
        )
        TravelTimeGateway.any_instance.stubs(:isochrone!).raises(
          TravelTimeGateway::ConfigError,
          "TravelTime requires both TRAVELTIME_API_KEY and TRAVELTIME_APP_ID"
        )

        get search_api_v1_properties_path, params: { query: "Bath Abbey" }, as: :json

        assert_response :service_unavailable
        assert_equal "TravelTime requires both TRAVELTIME_API_KEY and TRAVELTIME_APP_ID",
                     response.parsed_body["error"]
      end

      # ------------------------------------------------------------------
      # show
      # ------------------------------------------------------------------

      test "GET /api/v1/properties/:id returns property" do
        get api_v1_property_path(@active), as: :json
        assert_response :success
        assert_equal @active.rightmove_id, response.parsed_body["rightmove_id"]
      end

      test "GET /api/v1/properties/:id includes ml forecast when inference is available" do
        Ml::HousePriceForecastService.any_instance.stubs(:call).returns(
          {
            "current_price_pence" => 35_000_000,
            "forecasts" => [
              {
                "prediction_horizon_months" => 12,
                "predicted_future_price_pence" => 37_800_000,
                "predicted_growth_pct" => 8.0
              },
              {
                "prediction_horizon_months" => 24,
                "predicted_future_price_pence" => 39_200_000,
                "predicted_growth_pct" => 12.0
              }
            ]
          }
        )

        get api_v1_property_path(@active), as: :json

        assert_response :success
        assert_equal 37_800_000, response.parsed_body["ml_forecast"]["forecasts"].first["predicted_future_price_pence"]
        assert_equal 12.0, response.parsed_body["ml_forecast"]["forecasts"].second["predicted_growth_pct"]
      end

      test "GET /api/v1/properties/:id excludes raw_data" do
        get api_v1_property_path(@active), as: :json
        assert_not response.parsed_body.key?("raw_data")
      end

      test "GET /api/v1/properties/:id includes noise payload" do
        get api_v1_property_path(@active), as: :json
        assert_equal "england_noise_data", response.parsed_body["noise"]["provider"]
        assert_equal 62.1, response.parsed_body["noise"]["road_data"]["metrics"]["lden"]
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
