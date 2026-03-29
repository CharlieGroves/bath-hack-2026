require "json"
require "net/http"
require "uri"
require "csv"

# Reverse geocoding via https://nominatim.org/ (OpenStreetMap).
# Takes Nominatim’s comma-separated +display_name+ and returns the segment that is
# fifth from the end (e.g. often borough-level in UK addresses — depends on OSM).
#
# Nominatim requires a descriptive User-Agent and light usage (≈1 req/s for the
# public instance). See https://operations.osmfoundation.org/policies/nominatim/
#
# Usage:
#   Gateways::HousePriceGrowthGateway.new.fetch_house_growth_rows(latitude: 51.5074, longitude: -0.1278)
#   # => array of CSV rows (hashes); empty if no Nominatim segment or no matches
module Gateways
  class HousePriceGrowthGateway
    BASE = "https://nominatim.openstreetmap.org/reverse".freeze
    DATA_FILE = "london_area_house_growth_per_year.csv".freeze

    class Error < StandardError; end
    class RateLimitError < Error; end

    # @return [Array<Hash>] every row whose +area_name+ matches the geocoded segment:
    #   either string contains the other (case-insensitive). Multiple rows are all returned.
    def fetch_house_growth_rows(latitude:, longitude:)
      borough = fetch_borough(latitude: latitude, longitude: longitude)
      return [] if borough.blank?

      needle = borough.to_s.downcase.strip
      path   = Rails.root.join("data", DATA_FILE)
      raise Error, "Missing CSV: #{path}" unless path.file?

      table = CSV.read(path, headers: true)
      table.select do |row|
        field = row["area_name"].to_s.downcase.strip
        next false if field.empty?

        needle.include?(field) || field.include?(needle)
      end.map(&:to_h)
    end

    private

    # @return [String, nil] fifth comma-separated segment from the end of +display_name+
    def fetch_borough(latitude:, longitude:)
      payload = reverse_json(latitude: latitude, longitude: longitude)
      fifth_segment_from_end(payload["display_name"])
    end

    # display_name is typically "road, suburb, borough, city, county, postcode, country"
    # — exact order varies; this picks parts[-5] after splitting on commas.
    def fifth_segment_from_end(display_name)
      return nil if display_name.blank?

      parts = display_name.split(",").map(&:strip).reject(&:empty?)
      return nil if parts.size < 5

      parts[-5].presence
    end

    def reverse_json(latitude:, longitude:)
      uri = URI(BASE)
      uri.query = URI.encode_www_form(
        lat: latitude.to_f,
        lon: longitude.to_f,
        format: "json",
        addressdetails: 1
      )

      body = get(uri)
      JSON.parse(body)
    rescue JSON::ParserError => e
      raise Error, "Invalid JSON from Nominatim: #{e.message}"
    end

    def get(uri)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        req = Net::HTTP::Get.new(uri)
        req["Accept"] = "application/json"
        req["Accept-Language"] = "en"
        req["User-Agent"] = "BathHack/1.0 (property map; +https://github.com/CharlieGroves/bath-hack-2026)"
        http.request(req)
      end

      raise RateLimitError, "Nominatim HTTP 429 for #{uri}" if response.code == "429"
      raise Error, "Nominatim HTTP #{response.code} for #{uri}" unless response.is_a?(Net::HTTPSuccess)

      response.body
    end
  end
end
