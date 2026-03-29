require "json"

class TravelTimeGeocoder
  BASE_URL = "https://api.traveltimeapp.com".freeze

  class Error < StandardError; end
  class LocationNotFound < Error; end
  class RequestError < Error; end

  def initialize(connection: Faraday.new(url: BASE_URL),
                 api_key: ENV["TRAVELTIME_API_KEY"],
                 application_id: ENV["TRAVELTIME_APP_ID"])
    @connection = connection
    @api_key = api_key
    @application_id = application_id
  end

  def search!(query)
    response = @connection.get("/v4/geocoding/search") do |request|
      request.headers["Accept"] = "application/json"
      request.headers["X-Api-Key"] = @api_key
      request.headers["X-Application-Id"] = @application_id
      request.params["query"] = query
      request.params["limit"] = 1
    end

    raise RequestError, "Location lookup failed with status #{response.status}" unless response.success?

    payload = JSON.parse(response.body.to_s)
    match = Array(payload.dig("features")).first
    raise LocationNotFound, %(No location found for "#{query}") if match.nil?

    coordinates = match.dig("geometry", "coordinates")
    label = match.dig("properties", "label").presence || query

    {
      latitude: coordinates[1].to_f,
      longitude: coordinates[0].to_f,
      label: label
    }
  rescue Faraday::Error => e
    raise RequestError, "Location lookup failed: #{e.message}"
  rescue JSON::ParserError => e
    raise RequestError, "Location lookup returned invalid JSON: #{e.message}"
  end
end
