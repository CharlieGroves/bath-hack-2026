class CrimeAreaSnapshotJob < ApplicationJob
  queue_as :crime

  retry_on CrimeRate::RateLimitError, wait: :exponentially_longer, attempts: 12

  sidekiq_options throttle: { threshold: { limit: 1, period: 1 } }

  MONTHS = 3

  def perform(property_ids)
    properties = Property.where(id: property_ids).to_a
    return if properties.empty?

    anchor = properties.first
    return if anchor.latitude.blank? || anchor.longitude.blank?

    avg = CrimeRateGateway.average_crime_rate(
      lat:        anchor.latitude,
      lng:        anchor.longitude,
      crime_type: "all-crime",
      months:     MONTHS
    )

    now = Time.current
    properties.each do |property|
      snapshot = property.property_crime_snapshot || property.build_property_crime_snapshot
      snapshot.update!(
        latitude:           property.latitude,
        longitude:          property.longitude,
        avg_monthly_crimes: avg,
        fetched_at:         now,
        status:             "ready",
        error_message:      nil
      )
    end
  rescue CrimeRate::RateLimitError
    raise
  rescue CrimeRate::RequestError => e
    now = Time.current
    Property.where(id: property_ids).find_each do |property|
      snapshot = property.property_crime_snapshot || property.build_property_crime_snapshot
      snapshot.update!(
        latitude:      property.latitude,
        longitude:     property.longitude,
        status:        "failed",
        error_message: e.message,
        fetched_at:    now
      )
    end
    raise
  end
end
