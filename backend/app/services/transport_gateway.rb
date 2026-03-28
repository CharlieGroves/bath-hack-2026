require "json"
require "open3"
require "uri"

class TransportGateway
  class Error < StandardError; end
  PROVIDER = "england_noise_data".freeze

  def initialize(rail_gateway: EnglandRailNoiseGateway.new,
                 flight_gateway: EnglandFlightNoiseGateway.new,
                 road_gateway: EnglandRoadNoiseGateway.new)
    @rail_gateway = rail_gateway
    @flight_gateway = flight_gateway
    @road_gateway = road_gateway
  end

  def fetch(latitude:, longitude:)
    {
      provider: PROVIDER,
      flight_data: @flight_gateway.fetch(latitude: latitude, longitude: longitude),
      rail_data: @rail_gateway.fetch(latitude: latitude, longitude: longitude),
      road_data: @road_gateway.fetch(latitude: latitude, longitude: longitude)
    }
  end
end

class EnglandFlightNoiseGateway
  def initialize(sampler: EnglandNoiseSampler.new(
    cache_key_prefix: "airport",
    dataset_id: "dac9cba4-abe7-43bd-b8e9-8a83da52edd8",
    coverage_prefix: "Airport_Noise_ALL_",
    metrics: {
      "laeq16hr" => "LAeq16hr",
      "lday" => "Lday",
      "lden" => "Lden",
      "leve" => "Leve",
      "lnight" => "Lnight"
    },
    origin_easting: 333490.0,
    origin_northing: 574280.0,
    bounds: {
      min_easting: 333485.0,
      min_northing: 93815.0,
      max_easting: 594465.0,
      max_northing: 574285.0
    }
  ))
    @sampler = sampler
  end

  def fetch(latitude:, longitude:)
    @sampler.fetch(latitude: latitude, longitude: longitude)
  end
end

class EnglandRailNoiseGateway
  def initialize(sampler: EnglandNoiseSampler.new(
    cache_key_prefix: "rail",
    dataset_id: "3fb3c2d7-292c-4e0a-bd5b-d8e4e1fe2947",
    coverage_prefix: "Rail_Noise_",
    coverage_suffix: "_England_Round_4_All",
    metrics: {
      "laeq06hr" => "LAeq06hr",
      "laeq16hr" => "LAeq16hr",
      "laeq18hr" => "LAeq18hr",
      "lday" => "Lday",
      "lden" => "Lden",
      "leve" => "Leve",
      "lnight" => "Lnight"
    },
    origin_easting: 82650.0,
    origin_northing: 657600.0,
    bounds: {
      min_easting: 82645.0,
      min_northing: 5335.0,
      max_easting: 655995.0,
      max_northing: 657605.0
    }
  ))
    @sampler = sampler
  end

  def fetch(latitude:, longitude:)
    @sampler.fetch(latitude: latitude, longitude: longitude)
  end
end

class EnglandRoadNoiseGateway
  def initialize(sampler: EnglandNoiseSampler.new(
    cache_key_prefix: "road",
    dataset_id: "562c9d56-7c2d-4d42-83bb-578d6e97a517",
    coverage_prefix: "Road_Noise_",
    coverage_suffix: "_England_Round_4_All",
    metrics: {
      "laeq16hr" => "LAeq16hr",
      "lday" => "Lday",
      "lden" => "Lden",
      "leve" => "Leve",
      "lnight" => "Lnight"
    },
    origin_easting: 82650.0,
    origin_northing: 657600.0,
    bounds: {
      min_easting: 82645.0,
      min_northing: 5335.0,
      max_easting: 655995.0,
      max_northing: 657605.0
    }
  ))
    @sampler = sampler
  end

  def fetch(latitude:, longitude:)
    @sampler.fetch(latitude: latitude, longitude: longitude)
  end
end

class EnglandNoiseSampler
  RESOLUTION = 10.0
  NULL_VALUE = -96.0
  BASE_URL = "https://environment.data.gov.uk".freeze

  def initialize(cache_key_prefix:, dataset_id:, coverage_prefix:, metrics:, origin_easting:, origin_northing:, bounds:, coverage_suffix: "", base_url: BASE_URL)
    @cache_key_prefix = cache_key_prefix
    @dataset_id = dataset_id
    @coverage_prefix = coverage_prefix
    @coverage_suffix = coverage_suffix
    @metrics = metrics
    @origin_easting = origin_easting
    @origin_northing = origin_northing
    @bounds = bounds
    @base_url = base_url
  end

  def fetch(latitude:, longitude:)
    easting, northing = BritishNationalGrid.from_wgs84(latitude.to_f, longitude.to_f)
    return empty_payload(easting, northing) unless within_bounds?(easting, northing)

    cell = sample_cell(easting, northing)

    Rails.cache.fetch(cache_key(cell), expires_in: 7.days) do
      metrics = @metrics.transform_values do |metric_name|
        sample_metric(
          coverage_id: coverage_id(metric_name),
          min_easting: cell[:min_easting],
          max_easting: cell[:max_easting],
          min_northing: cell[:min_northing],
          max_northing: cell[:max_northing]
        )
      end

      {
        "covered" => metrics.values.compact.any?,
        "easting" => easting.round(3),
        "northing" => northing.round(3),
        "metrics" => metrics
      }
    end
  end

  private

  def cache_key(cell)
    [
      "england-noise",
      @cache_key_prefix,
      cell[:min_easting],
      cell[:min_northing]
    ].join(":")
  end

  def coverage_id(metric_name)
    "#{@dataset_id}__#{@coverage_prefix}#{metric_name}#{@coverage_suffix}"
  end

  def empty_payload(easting, northing)
    {
      "covered" => false,
      "easting" => easting.round(3),
      "northing" => northing.round(3),
      "metrics" => @metrics.keys.index_with { nil }
    }
  end

  def within_bounds?(easting, northing)
    easting >= @bounds[:min_easting] &&
      easting <= @bounds[:max_easting] &&
      northing >= @bounds[:min_northing] &&
      northing <= @bounds[:max_northing]
  end

  def sample_cell(easting, northing)
    column = ((easting - @origin_easting) / RESOLUTION).floor
    row = ((@origin_northing - northing) / RESOLUTION).floor
    centre_easting = @origin_easting + (column * RESOLUTION)
    centre_northing = @origin_northing - (row * RESOLUTION)

    {
      min_easting: (centre_easting - (RESOLUTION / 2)).round(3),
      max_easting: (centre_easting + (RESOLUTION / 2)).round(3),
      min_northing: (centre_northing - (RESOLUTION / 2)).round(3),
      max_northing: (centre_northing + (RESOLUTION / 2)).round(3)
    }
  end

  def sample_metric(coverage_id:, min_easting:, max_easting:, min_northing:, max_northing:)
    query = URI.encode_www_form(
      [
        ["service", "WCS"],
        ["version", "2.0.1"],
        ["request", "GetCoverage"],
        ["coverageId", coverage_id],
        ["subset", "E(#{min_easting},#{max_easting})"],
        ["subset", "N(#{min_northing},#{max_northing})"],
        ["format", "text/plain"]
      ]
    )

    url = "#{@base_url}/geoservices/datasets/#{@dataset_id}/wcs?#{query}"
    stdout, stderr, status = Open3.capture3(
      "curl",
      "--silent",
      "--show-error",
      "--location",
      "--connect-timeout",
      "10",
      "--max-time",
      "30",
      url
    )

    raise TransportGateway::Error, "curl failed for England noise data: #{stderr.presence || status.exitstatus}" unless status.success?

    parse_value(stdout.to_s)
  end

  def parse_value(body)
    match = body.match(/Band 0:\s*(-?\d+(?:\.\d+)?)/)
    return nil unless match

    value = match[1].to_f
    return nil if value == NULL_VALUE

    value.round(3)
  end
end

class BritishNationalGrid
  WGS84_A = 6_378_137.0
  WGS84_B = 6_356_752.314245
  AIRY1830_A = 6_377_563.396
  AIRY1830_B = 6_356_256.909

  def self.from_wgs84(latitude, longitude)
    lat = degrees_to_radians(latitude)
    lon = degrees_to_radians(longitude)
    x1, y1, z1 = lat_lon_to_cartesian(lat, lon, WGS84_A, WGS84_B)
    x2, y2, z2 = helmert_transform(x1, y1, z1)
    lat_osgb, lon_osgb = cartesian_to_lat_lon(x2, y2, z2, AIRY1830_A, AIRY1830_B)
    lat_lon_to_grid(lat_osgb, lon_osgb)
  end

  def self.degrees_to_radians(value)
    value * Math::PI / 180
  end

  def self.lat_lon_to_cartesian(lat, lon, a, b)
    e2 = 1 - ((b * b) / (a * a))
    sin_lat = Math.sin(lat)
    cos_lat = Math.cos(lat)
    sin_lon = Math.sin(lon)
    cos_lon = Math.cos(lon)
    v = a / Math.sqrt(1 - (e2 * sin_lat * sin_lat))

    [
      v * cos_lat * cos_lon,
      v * cos_lat * sin_lon,
      v * (1 - e2) * sin_lat
    ]
  end

  def self.helmert_transform(x, y, z)
    tx = -446.448
    ty = 125.157
    tz = -542.06
    rx = degrees_to_radians(-0.1502 / 3600)
    ry = degrees_to_radians(-0.2470 / 3600)
    rz = degrees_to_radians(-0.8421 / 3600)
    scale = 20.4894 * 1e-6 + 1

    [
      tx + (x * scale) - (y * rz) + (z * ry),
      ty + (x * rz) + (y * scale) - (z * rx),
      tz - (x * ry) + (y * rx) + (z * scale)
    ]
  end

  def self.cartesian_to_lat_lon(x, y, z, a, b)
    e2 = 1 - ((b * b) / (a * a))
    p = Math.sqrt((x * x) + (y * y))
    lat = Math.atan2(z, p * (1 - e2))

    loop do
      v = a / Math.sqrt(1 - (e2 * Math.sin(lat)**2))
      next_lat = Math.atan2(z + (e2 * v * Math.sin(lat)), p)
      if (next_lat - lat).abs < 1e-12
        lat = next_lat
        break
      end

      lat = next_lat
    end

    [lat, Math.atan2(y, x)]
  end

  def self.lat_lon_to_grid(lat, lon)
    f0 = 0.9996012717
    lat0 = degrees_to_radians(49)
    lon0 = degrees_to_radians(-2)
    n0 = -100_000
    e0 = 400_000
    e2 = 1 - ((AIRY1830_B * AIRY1830_B) / (AIRY1830_A * AIRY1830_A))
    n = (AIRY1830_A - AIRY1830_B) / (AIRY1830_A + AIRY1830_B)
    sin_lat = Math.sin(lat)
    cos_lat = Math.cos(lat)
    tan_lat = Math.tan(lat)
    nu = AIRY1830_A * f0 / Math.sqrt(1 - (e2 * sin_lat * sin_lat))
    rho = AIRY1830_A * f0 * (1 - e2) / ((1 - (e2 * sin_lat * sin_lat))**1.5)
    eta2 = (nu / rho) - 1
    m = meridional_arc(lat, lat0, n, f0)
    d_lon = lon - lon0
    i = m + n0
    ii = (nu / 2) * sin_lat * cos_lat
    iii = (nu / 24) * sin_lat * (cos_lat**3) * (5 - (tan_lat**2) + (9 * eta2))
    iiia = (nu / 720) * sin_lat * (cos_lat**5) * (61 - (58 * tan_lat**2) + (tan_lat**4))
    iv = nu * cos_lat
    v = (nu / 6) * (cos_lat**3) * ((nu / rho) - (tan_lat**2))
    vi = (nu / 120) * (cos_lat**5) * (5 - (18 * tan_lat**2) + (tan_lat**4) + (14 * eta2) - (58 * tan_lat**2 * eta2))
    northing = i + (ii * d_lon**2) + (iii * d_lon**4) + (iiia * d_lon**6)
    easting = e0 + (iv * d_lon) + (v * d_lon**3) + (vi * d_lon**5)

    [easting, northing]
  end

  def self.meridional_arc(lat, lat0, n, f0)
    ma = (1 + n + ((5.0 / 4.0) * n**2) + ((5.0 / 4.0) * n**3)) * (lat - lat0)
    mb = ((3 * n) + (3 * n**2) + ((21.0 / 8.0) * n**3)) * Math.sin(lat - lat0) * Math.cos(lat + lat0)
    mc = (((15.0 / 8.0) * n**2) + ((15.0 / 8.0) * n**3)) * Math.sin(2 * (lat - lat0)) * Math.cos(2 * (lat + lat0))
    md = (35.0 / 24.0) * n**3 * Math.sin(3 * (lat - lat0)) * Math.cos(3 * (lat + lat0))

    AIRY1830_B * f0 * (ma - mb + mc - md)
  end
end
