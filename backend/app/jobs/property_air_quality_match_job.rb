# Assigns a single property to its nearest air quality station using L2
# (Euclidean) distance over latitude and longitude.
#
# Enqueued automatically by RightmoveScrapeJob after a new property is created.
# Safe to re-enqueue at any time — will overwrite any existing assignment.
# Silently skips if no stations with DAQI data exist yet.
class PropertyAirQualityMatchJob < ApplicationJob
  queue_as :default

  def perform(property_id)
    property = Property.find_by(id: property_id)
    return unless property
    return if property.latitude.blank? || property.longitude.blank?

    stations = AirQualityStation.with_daqi.pluck(:id, :latitude, :longitude)
    if stations.empty?
      Rails.logger.warn("[PropertyAirQualityMatchJob] No DAQI stations in DB yet — skipping property #{property_id}")
      return
    end

    lat = property.latitude.to_f
    lon = property.longitude.to_f

    nearest_id = stations.min_by { |_id, slat, slon|
      (lat - slat.to_f)**2 + (lon - slon.to_f)**2
    }.first

    property.update_columns(air_quality_station_id: nearest_id)
    Rails.logger.info("[PropertyAirQualityMatchJob] Property #{property_id} → station #{nearest_id}")
  end
end
