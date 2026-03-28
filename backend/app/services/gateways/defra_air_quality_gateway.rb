require "faraday"
require "faraday/follow_redirects"

# Thin HTTP wrapper around the DEFRA UK-Air SOS REST API v1.
#
# Docs: https://uk-air.defra.gov.uk/data/about_sos
# Base: https://uk-air.defra.gov.uk/sos-ukair/api/v1
#
# Coordinate note: the API returns geometry.coordinates as [lat, lon, "NaN"]
# (non-standard — opposite of GeoJSON spec). Callers receive { latitude:, longitude: }.
class DefraAirQualityGateway
  class Error < StandardError; end

  BASE_URL         = "https://uk-air.defra.gov.uk/sos-ukair/api/v1".freeze
  MISSING_SENTINEL = -99.0

  # Bounding box for Greater London
  LONDON_LAT_MIN =  51.28
  LONDON_LAT_MAX =  51.70
  LONDON_LON_MIN = -0.51
  LONDON_LON_MAX =  0.34

  # EIONET pollutant URI suffix → canonical short name (DAQI pollutants only)
  POLLUTANT_MAP = {
    "1"    => "SO2",
    "5"    => "PM10",
    "7"    => "O3",
    "38"   => "NO2",
    "6001" => "PM2.5"
  }.freeze

  def initialize(conn: nil)
    @conn = conn || build_connection
  end

  # Returns an array of station hashes for stations within the London bbox:
  #   { external_id:, name:, latitude:, longitude:,
  #     timeseries: { "354" => "NO2", "789" => "PM10", ... } }
  #
  # Only timeseries whose phenomenon maps to a DAQI pollutant are included.
  # Stations with no matching DAQI timeseries are excluded.
  def fetch_london_stations
    body = get("stations", expanded: true)
    raise Error, "Expected array from stations, got #{body.class}" unless body.is_a?(Array)

    body.filter_map do |feature|
      props  = feature["properties"] || {}
      coords = (feature.dig("geometry", "coordinates") || [])

      lat = coords[0].to_f
      lon = coords[1].to_f

      next unless london?(lat, lon)

      ts_map = extract_daqi_timeseries(props["timeseries"] || {})
      next if ts_map.empty?

      {
        external_id: props["id"].to_i,
        name:        props["label"].to_s.strip,
        latitude:    lat,
        longitude:   lon,
        timeseries:  ts_map   # { "354" => "NO2", ... }
      }
    end
  end

  # Fetches the last +days+ days of hourly observations for one timeseries and
  # returns the mean of all valid readings, or nil if there are none.
  #
  # @param timeseries_id [String, Integer]
  # @param days          [Integer]
  # @return              [Float, nil]
  def fetch_recent_mean(timeseries_id:, days: 90)
    to   = Date.today
    from = to - days

    timespan = "#{from}T00:00:00Z/#{to}T23:59:59Z"
    body = get("timeseries/#{timeseries_id}/getData", timespan: timespan)

    values = (body["values"] || []).filter_map do |entry|
      next unless entry.is_a?(Hash)
      v = entry["value"]
      next if v.nil? || v.to_f == MISSING_SENTINEL
      v.to_f
    end

    return nil if values.empty?

    (values.sum / values.size.to_f).round(4)
  end

  private

  def london?(lat, lon)
    lat.between?(LONDON_LAT_MIN, LONDON_LAT_MAX) &&
      lon.between?(LONDON_LON_MIN, LONDON_LON_MAX)
  end

  def extract_daqi_timeseries(raw_ts)
    raw_ts.each_with_object({}) do |(ts_id, meta), acc|
      phenomenon_id = meta.dig("phenomenon", "id").to_s
      pollutant = pollutant_from_uri(phenomenon_id)
      acc[ts_id.to_s] = pollutant if pollutant
    end
  end

  def pollutant_from_uri(uri)
    suffix = uri.split("/").last
    POLLUTANT_MAP[suffix]
  end

  def get(path, params = {})
    resp = @conn.get(path, params)
    raise Error, "DEFRA API #{path} returned HTTP #{resp.status}" unless resp.success?

    JSON.parse(resp.body)
  rescue Faraday::Error => e
    raise Error, "DEFRA API request failed: #{e.message}"
  rescue JSON::ParserError => e
    raise Error, "DEFRA API returned invalid JSON: #{e.message}"
  end

  def build_connection
    Faraday.new(url: BASE_URL) do |f|
      f.response :follow_redirects
      f.headers["Accept"] = "application/json"
      f.options.timeout      = 30
      f.options.open_timeout = 10
    end
  end
end
