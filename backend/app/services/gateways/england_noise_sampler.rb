require "json"
require "open3"
require "uri"

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
