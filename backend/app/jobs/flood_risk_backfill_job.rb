# Backfills flood_risk_datapoint_id for all existing properties that don't
# yet have one assigned. Run once after importing the flood risk CSV:
#
#   FloodRiskBackfillJob.perform_later
class FloodRiskBackfillJob < ApplicationJob
  queue_as :default
  def perform
    datapoints = FloodRiskDatapoint.pluck(:id, :latitude, :longitude)
    if datapoints.empty?
      Rails.logger.warn("[FloodRiskBackfillJob] No flood risk datapoints in DB — run rake flood_risk:import first")
      return
    end

    scope = Property.where(flood_risk_datapoint_id: nil)
                    .where.not(latitude: nil, longitude: nil)

    assigned = 0
    scope.find_each do |property|
      lat = property.latitude.to_f
      lon = property.longitude.to_f

      nearest_id = datapoints.min_by { |_id, dlat, dlon|
        (lat - dlat.to_f)**2 + (lon - dlon.to_f)**2
      }.first

      property.update_columns(flood_risk_datapoint_id: nearest_id)
      assigned += 1
    end

    Rails.logger.info("[FloodRiskBackfillJob] Assigned #{assigned} properties to their nearest flood risk datapoint")
  end
end
