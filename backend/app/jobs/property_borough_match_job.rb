# Resolves the borough for a single property by reverse-geocoding its
# coordinates via Nominatim, normalising the result via BoroughNameNormaliser,
# and writing the borough_id foreign key.
#
# Enqueued by RightmoveScrapeJob after a new property is created.
# Rate-limited by Nominatim policy (~1 req/s) — the :default queue is fine for
# background use; avoid bursting many jobs simultaneously.
class PropertyBoroughMatchJob < ApplicationJob
  queue_as :default

  def perform(property_id)
    property = Property.find_by(id: property_id)
    return unless property
    return if property.latitude.blank? || property.longitude.blank?

    nominatim_name = Gateways::HousePriceGrowthGateway.new
                       .send(:fetch_borough,
                             latitude:  property.latitude,
                             longitude: property.longitude)

    canonical = BoroughNameNormaliser.normalise(nominatim_name)
    unless canonical
      Rails.logger.warn("[PropertyBoroughMatchJob] Unrecognised borough '#{nominatim_name}' for property #{property_id}")
      return
    end

    borough = Borough.find_by(name: canonical)
    unless borough
      Rails.logger.warn("[PropertyBoroughMatchJob] Borough '#{canonical}' not in DB — run BoroughImportJob first")
      return
    end

    property.update_columns(borough_id: borough.id)
    Rails.logger.info("[PropertyBoroughMatchJob] Property #{property_id} → borough '#{canonical}'")
  rescue Gateways::HousePriceGrowthGateway::Error => e
    Rails.logger.error("[PropertyBoroughMatchJob] Nominatim error for property #{property_id}: #{e.message}")
    raise
  end
end
