require "test_helper"

class PropertyLocationSearchTest < ActiveSupport::TestCase
  setup do
    PropertyTransportSnapshot.delete_all
    Property.delete_all
  end

  test "call geocodes the query, fetches an isochrone, and filters matching properties by polygon" do
    inside = create(:property, latitude: 51.3810, longitude: -2.3610)
    create(:property, latitude: 51.3890, longitude: -2.3490)

    geocoder = mock
    travel_time_gateway = mock

    geocoder.expects(:search!).with("Bath Abbey").returns(
      { latitude: 51.3811, longitude: -2.3590, label: "Bath Abbey, Bath, UK" }
    )
    travel_time_gateway.expects(:isochrone!).with(
      latitude: 51.3811,
      longitude: -2.3590,
      transportation_type: "walking",
      travel_time: 600
    ).returns(
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

    result = PropertyLocationSearch.new(
      scope: Property.order(created_at: :desc),
      geocoder: geocoder,
      travel_time_gateway: travel_time_gateway
    ).call(query: "  Bath Abbey  ", transportation_type: "walking", travel_time: 600)

    assert_equal "Bath Abbey", result[:query]
    assert_equal "Bath Abbey, Bath, UK", result[:location][:label]
    assert_equal "walking", result[:transportation_type]
    assert_equal 600, result[:travel_time_seconds]
    assert_equal({ north: 51.39, south: 51.37, east: -2.35, west: -2.37 }, result[:bounding_box])
    assert_equal 1, result[:isochrone_shells].length
    assert_equal [inside.id], result[:properties].pluck(:id)
  end

  test "call rejects a blank query" do
    error = assert_raises(PropertyLocationSearch::InvalidQuery) do
      PropertyLocationSearch.new.call(query: "   ")
    end

    assert_equal "Query can't be blank", error.message
  end

  test "call rejects unsupported transportation types" do
    error = assert_raises(PropertyLocationSearch::InvalidTransportationType) do
      PropertyLocationSearch.new.call(query: "Bath", transportation_type: "train")
    end

    assert_equal "Transportation type must be one of: driving, walking, cycling", error.message
  end

  test "call rejects travel times outside the supported range" do
    error = assert_raises(PropertyLocationSearch::InvalidTravelTime) do
      PropertyLocationSearch.new.call(query: "Bath", travel_time: 30)
    end

    assert_equal "Travel time must be between 1 and 120 minutes", error.message
  end
end
