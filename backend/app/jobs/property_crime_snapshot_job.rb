class PropertyCrimeSnapshotJob < ApplicationJob
  queue_as :crime

  retry_on CrimeRate::RateLimitError, wait: :exponentially_longer, attempts: 12

  sidekiq_options throttle: { threshold: { limit: 1, period: 1 } }

  MONTHS = 3

  def perform(property_id)
    property = Property.find_by(id: property_id)
    return unless property
    return if property.latitude.blank? || property.longitude.blank?

    if (neighbour = nearest_ready_snapshot(property))
      snapshot = property.property_crime_snapshot || property.build_property_crime_snapshot
      snapshot.update!(
        latitude:           property.latitude,
        longitude:          property.longitude,
        avg_monthly_crimes: neighbour.avg_monthly_crimes,
        fetched_at:         neighbour.fetched_at,
        status:             "ready",
        error_message:      nil
      )
      return
    end

    avg = CrimeRateGateway.average_crime_rate(
      lat:        property.latitude,
      lng:        property.longitude,
      crime_type: "all-crime",
      months:     MONTHS
    )

    snapshot = property.property_crime_snapshot || property.build_property_crime_snapshot
    snapshot.update!(
      latitude:           property.latitude,
      longitude:          property.longitude,
      avg_monthly_crimes: avg,
      fetched_at:         Time.current,
      status:             "ready",
      error_message:      nil
    )
  rescue CrimeRate::RateLimitError
    raise
  rescue CrimeRate::RequestError => e
    save_failure(property, e.message) if property
    raise
  end

  private

  def nearest_ready_snapshot(property)
    lat_bucket = (property.latitude.to_f  * 100).round / 100.0
    lng_bucket = (property.longitude.to_f * 100).round / 100.0
    tolerance  = 0.005 # half a bucket-width

    PropertyCrimeSnapshot
      .joins(:property)
      .where(status: "ready")
      .where(
        "properties.latitude  BETWEEN ? AND ? AND properties.longitude BETWEEN ? AND ?",
        lat_bucket - tolerance, lat_bucket + tolerance,
        lng_bucket - tolerance, lng_bucket + tolerance
      )
      .where.not(property_id: property.id)
      .order(fetched_at: :desc)
      .first
  end

  def save_failure(property, message)
    snapshot = property.property_crime_snapshot || property.build_property_crime_snapshot
    snapshot.update!(
      latitude:      property.latitude,
      longitude:     property.longitude,
      status:        "failed",
      error_message: message
    )
  end
end
