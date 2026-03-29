# Enqueues PropertyBoroughMatchJob for every property without a borough,
# staggered at 2-second intervals to stay within Nominatim's ~1 req/s limit.
#
#   BoroughBackfillJob.perform_later
class BoroughBackfillJob < ApplicationJob
  queue_as :default

  STAGGER_INTERVAL = 2.seconds

  def perform
    if Borough.none?
      Rails.logger.warn("[BoroughBackfillJob] No boroughs in DB — run BoroughImportJob first")
      return
    end

    scope = Property.where(borough_id: nil).where.not(latitude: nil, longitude: nil)
    count = scope.count
    Rails.logger.info("[BoroughBackfillJob] Enqueuing borough match for #{count} properties (staggered #{STAGGER_INTERVAL}s apart)…")

    scope.order(:id).each_with_index do |property, i|
      PropertyBoroughMatchJob
        .set(wait: i * STAGGER_INTERVAL)
        .perform_later(property.id)
    end
  end
end
