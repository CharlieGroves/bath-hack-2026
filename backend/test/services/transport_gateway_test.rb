require "test_helper"
require "cgi"
require "uri"

class TransportGatewayTest < ActiveSupport::TestCase
  setup do
    Rails.cache.clear
  end

  test "fetch returns normalized transport sections" do
    stub_request(:get, %r{\Ahttps://environment\.data\.gov\.uk/geoservices/datasets/.+/wcs\z})
      .to_return do |request|
        params = CGI.parse(URI(request.uri).query)
        coverage_id = params.fetch("coverageId").first

        value = case coverage_id
                when /Airport_Noise_ALL_Lden/ then 64.4
                when /Airport_Noise_ALL_Lday/ then 61.2
                when /Airport_Noise_ALL_Leve/ then 58.1
                when /Airport_Noise_ALL_Lnight/ then 53.7
                when /Airport_Noise_ALL_LAeq16hr/ then 60.5
                when /Rail_Noise_Lden_England_Round_4_All/ then 55.8
                when /Rail_Noise_Lday_England_Round_4_All/ then 53.2
                when /Rail_Noise_Leve_England_Round_4_All/ then 50.4
                when /Rail_Noise_Lnight_England_Round_4_All/ then 47.9
                when /Rail_Noise_LAeq06hr_England_Round_4_All/ then 46.0
                when /Rail_Noise_LAeq16hr_England_Round_4_All/ then 52.7
                when /Rail_Noise_LAeq18hr_England_Round_4_All/ then 54.3
                when /Road_Noise_Lden_England_Round_4_All/ then 62.1
                when /Road_Noise_Lday_England_Round_4_All/ then 59.0
                when /Road_Noise_Leve_England_Round_4_All/ then 56.2
                when /Road_Noise_Lnight_England_Round_4_All/ then 51.8
                when /Road_Noise_LAeq16hr_England_Round_4_All/ then 58.4
                else
                  raise "unexpected coverageId #{coverage_id}"
                end

        { status: 200, body: "Band 0:\n#{value}\n", headers: { "Content-Type" => "text/plain" } }
      end

    result = TransportGateway.new.fetch(latitude: 51.45, longitude: -0.3)

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
    stub_request(:get, %r{\Ahttps://environment\.data\.gov\.uk/geoservices/datasets/.+/wcs\z})
      .to_return(status: 502, body: "bad gateway")

    assert_raises(TransportGateway::Error) do
      TransportGateway.new.fetch(latitude: 51.45, longitude: -0.3)
    end
  end
end
