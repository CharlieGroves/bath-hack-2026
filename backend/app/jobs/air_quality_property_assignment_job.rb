# Assigns each property to its nearest air quality station using Euclidean
# distance on lat/long (sufficient accuracy at London scale).
#
# Only processes properties that either:
#   a) have no station assigned yet, or
#   b) are passed an explicit property_id for re-assignment.
#
# Run after AirQualityIngestJob (and its per-station children) have completed:
#   AirQualityPropertyAssignmentJob.perform_later
#
# Re-assign a single property:
#   AirQualityPropertyAssignmentJob.perform_later(property_id: 42)
class AirQualityPropertyAssignmentJob < ApplicationJob
  queue_as :default

  def perform(property_id: nil)
    stations = AirQualityStation.with_daqi.pluck(:id, :latitude, :longitude)

    if stations.empty?
      Rails.logger.warn("[AirQualityPropertyAssignmentJob] No stations with DAQI data yet — aborting")
      return
    end

    scope = property_id \
      ? Property.where(id: property_id) \
      : Property.where(air_quality_station_id: nil).where.not(latitude: nil, longitude: nil)

    assigned = 0
    scope.find_each do |property|
      nearest_id = nearest_station_id(stations, property.latitude.to_f, property.longitude.to_f)
      next unless nearest_id

      property.update_columns(air_quality_station_id: nearest_id)
      assigned += 1
    end

    Rails.logger.info("[AirQualityPropertyAssignmentJob] Assigned #{assigned} properties to their nearest station")
  end

  private

  # Returns the id of the station with smallest Euclidean distance to (lat, lon).
  # stations is an array of [id, lat, lon] triplets.
  def nearest_station_id(stations, lat, lon)
    stations.min_by { |_id, slat, slon| euclidean(lat, lon, slat.to_f, slon.to_f) }&.first
  end

  def euclidean(lat1, lon1, lat2, lon2)
    Math.sqrt((lat1 - lat2)**2 + (lon1 - lon2)**2)
  end
end
