# Fetches all London air quality stations from the DEFRA SOS REST API,
# upserts them into air_quality_stations, then enqueues one
# AirQualityStationIngestJob per station to pull 3 years of pollutant readings.
#
# Trigger from rails console or rake:
#   AirQualityIngestJob.perform_later
class AirQualityIngestJob < ApplicationJob
  queue_as :scraping

  def perform
    Rails.logger.info("[AirQualityIngestJob] Fetching London stations from DEFRA…")

    stations = AirQualityGateway.new.fetch_london_stations
    Rails.logger.info("[AirQualityIngestJob] Found #{stations.size} London stations with DAQI timeseries")

    stations.each do |station_data|
      record = upsert_station(station_data)
      AirQualityStationIngestJob.perform_later(record.id, station_data[:timeseries])
    end

    Rails.logger.info("[AirQualityIngestJob] Enqueued #{stations.size} station ingest jobs")
  rescue AirQualityGateway::Error => e
    Rails.logger.error("[AirQualityIngestJob] Failed to fetch stations: #{e.message}")
    raise
  end

  private

  def upsert_station(data)
    station = AirQualityStation.find_or_initialize_by(external_id: data[:external_id])
    station.assign_attributes(
      name:      data[:name],
      latitude:  data[:latitude],
      longitude: data[:longitude]
    )
    station.save!
    station
  end
end
