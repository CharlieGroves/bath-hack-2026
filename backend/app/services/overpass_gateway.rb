require "json"

class OverpassGateway
  ENDPOINT = "https://overpass-api.de/api/interpreter".freeze
  AMENITY_TYPES  = %w[school supermarket convenience pharmacy cafe].freeze
  RAILWAY_TYPES  = %w[station halt].freeze

  class Error < StandardError; end

  def initialize(connection: Faraday.new(url: ENDPOINT) { |f| f.options.timeout = 8; f.options.open_timeout = 4 })
    @connection = connection
  end

  # Returns array of { name:, amenity:, latitude:, longitude: }
  # Returns [] on any failure rather than raising — Overpass can be slow/flaky.
  def nearby_pois(latitude:, longitude:, radius_metres: 1000)
    query = build_query(latitude, longitude, radius_metres)

    response = @connection.get("") do |req|
      req.params["data"] = query
    end

    return [] unless response.success?

    parse_pois(JSON.parse(response.body.to_s))
  rescue Faraday::Error, JSON::ParserError
    []
  end

  private

  def build_query(lat, lng, radius)
    amenity_filter = AMENITY_TYPES.join("|")
    railway_filter = RAILWAY_TYPES.join("|")
    <<~OVERPASS.strip
      [out:json][timeout:10];
      (
        node(around:#{radius},#{lat},#{lng})[amenity~"#{amenity_filter}"];
        node(around:#{radius},#{lat},#{lng})[railway~"#{railway_filter}"];
      );
      out body;
    OVERPASS
  end

  def parse_pois(payload)
    Array(payload["elements"]).filter_map do |el|
      lat  = el["lat"]
      lng  = el["lon"]
      name = el.dig("tags", "name").presence
      amenity = el.dig("tags", "amenity") || el.dig("tags", "railway")

      next unless lat && lng && name && amenity

      {
        name: name,
        amenity: amenity,
        latitude: lat.to_f,
        longitude: lng.to_f
      }
    end
  end
end
