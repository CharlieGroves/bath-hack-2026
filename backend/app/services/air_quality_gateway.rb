require_relative "gateways/defra_air_quality_gateway"
require_relative "daqi_calculator"

# Application-facing entry point for DEFRA air quality data.
#
# For each station, fetches 90-day rolling means for every available DAQI
# pollutant timeseries and derives a single composite DAQI index (1–10).
#
# Usage:
#   gateway = AirQualityGateway.new
#
#   # List London stations (returns external_id, name, lat/lon, timeseries map)
#   gateway.fetch_london_stations
#
#   # Compute DAQI for one station
#   gateway.fetch_station_daqi(external_id: 123, timeseries: { "354" => "NO2", "789" => "PM10" })
#   # => { daqi_index: 5, daqi_band: "Moderate" }
class AirQualityGateway
  class Error < StandardError; end

  def initialize(defra: DefraAirQualityGateway.new)
    @defra = defra
  end

  def fetch_london_stations
    @defra.fetch_london_stations
  rescue DefraAirQualityGateway::Error => e
    raise Error, e.message
  end

  # Fetches 90-day means for each DAQI timeseries at this station and returns
  # the composite DAQI index and band.
  #
  # @param external_id [Integer]  DEFRA station external_id (used for logging)
  # @param timeseries  [Hash]     { "ts_id" => "pollutant_name", ... }
  # @return [Hash]  { daqi_index: Integer|nil, daqi_band: String|nil }
  def fetch_station_daqi(external_id:, timeseries:)
    means = {}

    timeseries.each do |ts_id, pollutant|
      mean = @defra.fetch_recent_mean(timeseries_id: ts_id)
      if mean
        # If multiple timeseries cover the same pollutant, keep the first valid one
        means[pollutant] ||= mean
      end
    rescue DefraAirQualityGateway::Error => e
      Rails.logger.warn("[AirQualityGateway] Station #{external_id} ts=#{ts_id}: #{e.message}")
    end

    composite = DaqiCalculator.composite(means)
    {
      daqi_index: composite,
      daqi_band:  DaqiCalculator.band_label(composite)
    }
  rescue DefraAirQualityGateway::Error => e
    raise Error, "Station #{external_id}: #{e.message}"
  end
end
