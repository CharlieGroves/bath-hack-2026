# Enqueues PropertyTransportSnapshotJob for all properties that don't yet
# have a ready noise snapshot — i.e. missing row, or status pending/failed.
# Safe to re-run: individual snapshot jobs are idempotent.
#
#   NoiseBackfillJob.perform_later
class NoiseBackfillJob < ApplicationJob
  queue_as :default

  def perform
    scope = Property
      .with_coordinates
      .where(
        "NOT EXISTS (" \
          "SELECT 1 FROM property_transport_snapshots pts " \
          "WHERE pts.property_id = properties.id AND pts.status = 'ready'" \
        ")"
      )

    count = 0
    scope.find_each do |property|
      PropertyTransportSnapshotJob.perform_later(property.id)
      count += 1
    end

    Rails.logger.info("[NoiseBackfillJob] Enqueued #{count} transport snapshot jobs")
  end
end
