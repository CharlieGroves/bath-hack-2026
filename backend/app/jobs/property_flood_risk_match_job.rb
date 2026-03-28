# Assigns a single property to its nearest flood risk datapoint using L2
# (Euclidean) distance over latitude and longitude.
#
# Enqueued automatically by RightmoveScrapeJob after a new property is created.
# Safe to re-enqueue at any time — overwrites any existing assignment.
# Silently skips if the flood risk table is empty (not yet imported).
class PropertyFloodRiskMatchJob < ApplicationJob
  queue_as :default

  def perform(property_id)
    property = Property.find_by(id: property_id)
    return unless property
    return if property.latitude.blank? || property.longitude.blank?

    datapoints = FloodRiskDatapoint.pluck(:id, :latitude, :longitude)
    if datapoints.empty?
      Rails.logger.warn("[PropertyFloodRiskMatchJob] No flood risk datapoints in DB yet — skipping property #{property_id}")
      return
    end

    lat = property.latitude.to_f
    lon = property.longitude.to_f

    nearest_id = datapoints.min_by { |_id, dlat, dlon|
      (lat - dlat.to_f)**2 + (lon - dlon.to_f)**2
    }.first

    property.update_columns(flood_risk_datapoint_id: nearest_id)
    Rails.logger.info("[PropertyFloodRiskMatchJob] Property #{property_id} → flood risk datapoint #{nearest_id}")
  end
end
