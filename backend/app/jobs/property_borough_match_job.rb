# Resolves the borough for a single property by reverse-geocoding its
# coordinates via Nominatim, normalising the result via BoroughNameNormaliser,
# and writing the borough_id foreign key.
#
# Enqueued by RightmoveScrapeJob after a new property is created.
#
# Nominatim's public instance enforces ~1 req/s. BoroughBackfillJob staggers
# jobs at 2-second intervals so they don't pile up. On a 429 this job reschedules
# itself 60 seconds later rather than burning Sidekiq's exponential retry budget.
class PropertyBoroughMatchJob < ApplicationJob
  queue_as :default

  # On 429 reschedule once per minute for up to 10 attempts before giving up.
  retry_on Gateways::HousePriceGrowthGateway::RateLimitError,
           wait: 60.seconds,
           attempts: 10

  # Other gateway errors (network, 5xx): standard exponential backoff.
  retry_on Gateways::HousePriceGrowthGateway::Error,
           wait: :polynomially_longer,
           attempts: 5

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
  end
end
