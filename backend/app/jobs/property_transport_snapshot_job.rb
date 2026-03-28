class PropertyTransportSnapshotJob < ApplicationJob
  queue_as :default

  def perform(property_id)
    property = Property.find_by(id: property_id)
    return unless property
    return if property.latitude.blank? || property.longitude.blank?

    payload = TransportGateway.new.fetch(latitude: property.latitude, longitude: property.longitude)
    snapshot = property.property_transport_snapshot || property.build_property_transport_snapshot

    snapshot.update!(
      provider: payload.fetch(:provider),
      latitude: property.latitude,
      longitude: property.longitude,
      flight_data: payload.fetch(:flight_data, {}),
      rail_data: payload.fetch(:rail_data, {}),
      road_data: payload.fetch(:road_data, {}),
      fetched_at: Time.current,
      status: "ready",
      error_message: nil
    )
  rescue TransportGateway::Error => e
    save_failure(property, e.message) if property
    raise
  end

  private

  def save_failure(property, message)
    snapshot = property.property_transport_snapshot || property.build_property_transport_snapshot

    snapshot.update!(
      provider: TransportGateway::PROVIDER,
      latitude: property.latitude,
      longitude: property.longitude,
      status: "failed",
      error_message: message
    )
  end
end
