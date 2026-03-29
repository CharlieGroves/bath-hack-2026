require "json"

class GoogleGeocoder
  BASE_URL = "https://maps.googleapis.com".freeze

  class Error < StandardError; end
  class LocationNotFound < Error; end
  class RequestError < Error; end

  def initialize(connection: Faraday.new(url: BASE_URL),
                 api_key: ENV["GOOGLE_API_KEY"])
    @connection = connection
    @api_key = api_key
  end

  def search!(query)
    response = @connection.get("/maps/api/geocode/json") do |request|
      request.params["address"] = query
      request.params["key"] = @api_key
    end

    raise RequestError, "Location lookup failed with status #{response.status}" unless response.success?

    payload = JSON.parse(response.body.to_s)

    if payload["status"] == "REQUEST_DENIED"
      raise RequestError, "Location lookup failed: #{payload['error_message']}"
    end

    match = Array(payload["results"]).first
    raise LocationNotFound, %(No location found for "#{query}") if match.nil?

    location = match.dig("geometry", "location")
    {
      latitude: location.fetch("lat").to_f,
      longitude: location.fetch("lng").to_f,
      label: match["formatted_address"].presence || query
    }
  rescue Faraday::Error => e
    raise RequestError, "Location lookup failed: #{e.message}"
  rescue JSON::ParserError => e
    raise RequestError, "Location lookup returned invalid JSON: #{e.message}"
  end
end
