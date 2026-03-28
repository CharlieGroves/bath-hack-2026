require "json"
require "net/http"
require "uri"

# Client for https://data.police.uk — street-level crime by category and coordinates.
#
# Valid category slugs include those returned by GET /api/crime-categories
# (e.g. "burglary", "vehicle-crime", "all-crime").
#
# Usage:
#   CrimeRate.fetch_street_crimes(
#     category: "burglary",
#     lat: 52.629729,
#     lng: -1.131592,
#     date: "2024-01"
#   )
class CrimeRate
  BASE = "https://data.police.uk/api/crimes-street".freeze

  class RequestError < StandardError; end
  class RateLimitError < RequestError; end

  # @param category [String] crime category slug (path segment), e.g. "all-crime", "burglary"
  # @param lat [Numeric] latitude
  # @param lng [Numeric] longitude
  # @param date [String, nil] optional month in YYYY-MM form
  # @return [Array<Hash>] parsed JSON array of crime objects
  def self.fetch_street_crimes(category:, lat:, lng:, date: nil)
    new.fetch_street_crimes(category: category, lat: lat, lng: lng, date: date)
  end

  def fetch_street_crimes(category:, lat:, lng:, date: nil)
    uri = URI("#{BASE}/#{escape_path_segment(category)}")
    uri.query = URI.encode_www_form(
      { lat: lat.to_f, lng: lng.to_f, **(date ? { date: date } : {}) }
    )

    body = get_json(uri)
    JSON.parse(body)
  rescue JSON::ParserError => e
    raise RequestError, "Invalid JSON from #{uri}: #{e.message}"
  end

  private

  def escape_path_segment(segment)
    # Avoid slashes in user input breaking the path; hyphens/letters stay as-is.
    segment.to_s.gsub(%r{[^A-Za-z0-9\-_.~]}, "")
  end

  def get_json(uri)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      req = Net::HTTP::Get.new(uri)
      req["Accept"] = "application/json"
      req["User-Agent"] = "BathHack/1.0 (crime data)"
      http.request(req)
    end

    raise RateLimitError, "HTTP 429 for #{uri}" if response.code == "429"
    raise RequestError, "HTTP #{response.code} for #{uri}" unless response.is_a?(Net::HTTPSuccess)

    response.body
  end
end
