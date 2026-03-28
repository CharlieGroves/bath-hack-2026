# Enqueues PropertyBoroughMatchJob for every property without a borough.
# Staggers jobs to avoid hammering the Nominatim rate limit.
#
#   BoroughBackfillJob.perform_later
class BoroughBackfillJob < ApplicationJob
  queue_as :default

  def perform
    if Borough.none?
      Rails.logger.warn("[BoroughBackfillJob] No boroughs in DB — run BoroughImportJob first")
      return
    end

    scope = Property.where(borough_id: nil).where.not(latitude: nil, longitude: nil)
    count = scope.count
    Rails.logger.info("[BoroughBackfillJob] Enqueuing borough match for #{count} properties…")

    scope.find_each do |property|
      PropertyBoroughMatchJob.perform_later(property.id)
    end
  end
end
