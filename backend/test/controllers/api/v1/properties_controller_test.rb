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

      test "GET /api/v1/properties filters by shared ownership flag" do
        @active.update!(description: "Buy a 35% share of this property via shared ownership")
        @under_offer.update!(description: "Traditional freehold sale")

        get api_v1_properties_path, params: { is_shared_ownership: true }, as: :json
        ids = response.parsed_body["properties"].map { |p| p["rightmove_id"] }

        assert_includes ids, @active.rightmove_id
        assert_not_includes ids, @under_offer.rightmove_id
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
            "forecasts" => [
              {
                "years_ahead" => 1,
                "predicted_future_price_pence" => 37_800_000,
                "prediction_interval_95" => {
                  "lower_pence" => 33_500_000,
                  "upper_pence" => 42_100_000
                }
              },
              {
                "years_ahead" => 2,
                "predicted_future_price_pence" => 39_200_000,
                "prediction_interval_95" => {
                  "lower_pence" => 34_200_000,
                  "upper_pence" => 44_200_000
                }
              }
            ]
          }
        )
        Ml::HousePriceValuationService.any_instance.stubs(:call).returns(nil)

        get api_v1_property_path(@active), as: :json

        assert_response :success
        assert_equal ["forecasts"], response.parsed_body["ml_forecast"].keys
        assert_equal 37_800_000, response.parsed_body["ml_forecast"]["forecasts"].first["predicted_future_price_pence"]
        assert_equal 44_200_000, response.parsed_body["ml_forecast"]["forecasts"].second["prediction_interval_95"]["upper_pence"]
      end

      test "GET /api/v1/properties/:id includes ml valuation when inference is available" do
        Ml::HousePriceForecastService.any_instance.stubs(:call).returns(nil)
        Ml::HousePriceValuationService.any_instance.stubs(:call).returns(
          {
            "predicted_current_price_pence" => 34_500_000,
            "pricing_signal" => "overpriced",
            "price_gap_pence" => 500_000,
            "price_gap_pct" => 1.45,
            "prediction_interval_80" => {
              "lower_pence" => 31_000_000,
              "upper_pence" => 36_800_000
            },
            "prediction_interval_95" => {
              "lower_pence" => 29_400_000,
              "upper_pence" => 38_200_000
            },
            "model_source" => "out_of_fold",
            "feature_weights" => [
              {
                "feature_key" => "size_sqft",
                "label" => "Size (sq ft)",
                "display_value" => "1,400",
                "normalized_weight" => 0.33,
                "absolute_weight" => 0.33,
                "direction" => "positive"
              }
            ]
          }
        )

        get api_v1_property_path(@active), as: :json

        assert_response :success
        assert_equal "overpriced", response.parsed_body["ml_valuation"]["pricing_signal"]
        assert_equal 34_500_000, response.parsed_body["ml_valuation"]["predicted_current_price_pence"]
        assert_equal 0.33, response.parsed_body["ml_valuation"]["feature_weights"].first["normalized_weight"]
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

      test "GET /api/v1/properties payload includes shared ownership flag" do
        @active.update!(description: "Shared ownership with 25% share available")

        get api_v1_property_path(@active), as: :json

        assert_equal true, response.parsed_body["is_shared_ownership"]
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
