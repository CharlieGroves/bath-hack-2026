require "json"

class NominatimGeocoder
  BASE_URL = "https://nominatim.openstreetmap.org".freeze
  USER_AGENT = "bath-hack-2026-property-search/1.0".freeze

  class Error < StandardError; end
  class LocationNotFound < Error; end
  class RequestError < Error; end

  def initialize(connection: Faraday.new(url: BASE_URL))
    @connection = connection
  end

  def search!(query)
    response = @connection.get("/search") do |request|
      request.headers["Accept"] = "application/json"
      request.headers["User-Agent"] = USER_AGENT
      request.params["q"] = query
      request.params["format"] = "jsonv2"
      request.params["limit"] = 1
    end

    raise RequestError, "Location lookup failed with status #{response.status}" unless response.success?

    payload = JSON.parse(response.body.to_s)
    match = payload.first
    raise LocationNotFound, %(No location found for "#{query}") if match.blank?

    {
      latitude: match.fetch("lat").to_f,
      longitude: match.fetch("lon").to_f,
      label: match["display_name"].presence || query
    }
  rescue Faraday::Error => e
    raise RequestError, "Location lookup failed: #{e.message}"
  rescue JSON::ParserError => e
    raise RequestError, "Location lookup returned invalid JSON: #{e.message}"
  end
end
