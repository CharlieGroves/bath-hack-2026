# Computes and stores a single DAQI index for one air quality station by
# fetching 90-day rolling means for each of its DAQI pollutant timeseries.
#
# Enqueued by AirQualityIngestJob — one job per station.
class AirQualityStationIngestJob < ApplicationJob
  queue_as :scraping

  # @param station_id [Integer]  ActiveRecord id of AirQualityStation
  # @param timeseries [Hash]     { "ts_id" => "pollutant_name", ... }
  def perform(station_id, timeseries)
    station = AirQualityStation.find_by(id: station_id)
    unless station
      Rails.logger.warn("[AirQualityStationIngestJob] Station #{station_id} not found, skipping")
      return
    end

    result = AirQualityGateway.new.fetch_station_daqi(
      external_id: station.external_id,
      timeseries:  timeseries
    )

    station.update!(
      daqi_index:          result[:daqi_index],
      daqi_band:           result[:daqi_band],
      readings_fetched_at: Time.current
    )

    Rails.logger.info(
      "[AirQualityStationIngestJob] #{station.name} → " \
      "DAQI #{result[:daqi_index]} (#{result[:daqi_band]})"
    )
  rescue AirQualityGateway::Error => e
    Rails.logger.error("[AirQualityStationIngestJob] Station #{station_id}: #{e.message}")
    raise
  end
end
