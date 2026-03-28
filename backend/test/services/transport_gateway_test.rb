require "test_helper"
class TransportGatewayTest < ActiveSupport::TestCase
  setup do
    Rails.cache.clear
  end

  test "fetch returns normalized transport sections" do
    flight_gateway = mock
    rail_gateway = mock
    road_gateway = mock

    flight_gateway.stubs(:fetch).returns(
      { "covered" => true, "metrics" => { "lden" => 64.4, "laeq16hr" => 60.5 } }
    )
    rail_gateway.stubs(:fetch).returns(
      { "covered" => true, "metrics" => { "lden" => 55.8, "laeq06hr" => 46.0 } }
    )
    road_gateway.stubs(:fetch).returns(
      { "covered" => true, "metrics" => { "lden" => 62.1, "laeq16hr" => 58.4 } }
    )

    result = TransportGateway.new(
      flight_gateway: flight_gateway,
      rail_gateway: rail_gateway,
      road_gateway: road_gateway
    ).fetch(latitude: 51.45, longitude: -0.3)

    assert_equal "england_noise_data", result[:provider]
    assert_equal true, result[:flight_data]["covered"]
    assert_equal 64.4, result[:flight_data]["metrics"]["lden"]
    assert_equal 60.5, result[:flight_data]["metrics"]["laeq16hr"]
    assert_equal true, result[:rail_data]["covered"]
    assert_equal 55.8, result[:rail_data]["metrics"]["lden"]
    assert_equal 46.0, result[:rail_data]["metrics"]["laeq06hr"]
    assert_equal true, result[:road_data]["covered"]
    assert_equal 62.1, result[:road_data]["metrics"]["lden"]
    assert_equal 58.4, result[:road_data]["metrics"]["laeq16hr"]
  end

  test "fetch raises on non-success responses" do
    flight_gateway = mock
    rail_gateway = mock
    road_gateway = mock

    flight_gateway.stubs(:fetch).raises(TransportGateway::Error, "bad gateway")
    rail_gateway.stubs(:fetch).returns({})
    road_gateway.stubs(:fetch).returns({})

    error = assert_raises(TransportGateway::Error) do
      TransportGateway.new(
        flight_gateway: flight_gateway,
        rail_gateway: rail_gateway,
        road_gateway: road_gateway
      ).fetch(latitude: 51.45, longitude: -0.3)
    end

    assert_equal "bad gateway", error.message
  end
end
