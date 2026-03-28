require "json"

class TravelTimeGateway
  BASE_URL = "https://api.traveltimeapp.com".freeze
  DEFAULT_SEARCH_ID = "property-search".freeze

  class Error < StandardError; end
  class ConfigError < Error; end
  class RequestError < Error; end

  def initialize(connection: Faraday.new(url: BASE_URL),
                 api_key: ENV["TRAVELTIME_API_KEY"],
                 application_id: ENV["TRAVELTIME_APP_ID"])
    @connection = connection
    @api_key = api_key
    @application_id = application_id
  end

  def isochrone!(latitude:, longitude:, travel_time:, transportation_type:, departure_time: Time.current)
    ensure_configured!

    response = @connection.post("/v4/time-map") do |request|
      request.headers["Accept"] = "application/json"
      request.headers["Content-Type"] = "application/json"
      request.headers["X-Api-Key"] = @api_key
      request.headers["X-Application-Id"] = @application_id
      request.body = JSON.generate(
        departure_searches: [
          {
            id: DEFAULT_SEARCH_ID,
            coords: {
              lat: latitude.to_f,
              lng: longitude.to_f
            },
            transportation: {
              type: transportation_type
            },
            departure_time: departure_time.utc.iso8601,
            travel_time: travel_time.to_i
          }
        ]
      )
    end

    raise RequestError, error_message_for(response) unless response.success?

    extract_isochrone(JSON.parse(response.body.to_s))
  rescue Faraday::Error => e
    raise RequestError, "TravelTime request failed: #{e.message}"
  rescue JSON::ParserError => e
    raise RequestError, "TravelTime returned invalid JSON: #{e.message}"
  end

  private

  def ensure_configured!
    return if @api_key.present? && @application_id.present?

    raise ConfigError, "TravelTime requires both TRAVELTIME_API_KEY and TRAVELTIME_APP_ID"
  end

  def error_message_for(response)
    message = nil
    payload = JSON.parse(response.body.to_s)
    message = payload["description"].presence || payload["error"].presence
    return "TravelTime request failed with status #{response.status}: #{message}" if message.present?
  rescue JSON::ParserError
    nil
  ensure
    return "TravelTime request failed with status #{response.status}" unless message.present?
  end

  def extract_isochrone(payload)
    shells = Array(payload["results"]).flat_map do |result|
      Array(result["shapes"]).filter_map do |shape|
        shell = normalize_shell(shape["shell"])
        next if shell.empty?

        shell
      end
    end

    raise RequestError, "TravelTime did not return any isochrone geometry" if shells.empty?

    coordinates = shells.flatten(1)

    {
      shells: shells,
      bounding_box: {
        north: coordinates.max_by { |coordinate| coordinate[:latitude] }.fetch(:latitude).round(6),
        south: coordinates.min_by { |coordinate| coordinate[:latitude] }.fetch(:latitude).round(6),
        east: coordinates.max_by { |coordinate| coordinate[:longitude] }.fetch(:longitude).round(6),
        west: coordinates.min_by { |coordinate| coordinate[:longitude] }.fetch(:longitude).round(6)
      }
    }
  end

  def normalize_shell(shell)
    Array(shell).filter_map do |coordinate|
      lat = coordinate["lat"]
      lng = coordinate["lng"]
      next if lat.blank? || lng.blank?

      {
        latitude: lat.to_f,
        longitude: lng.to_f
      }
    end
  end
end
