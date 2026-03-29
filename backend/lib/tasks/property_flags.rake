namespace :properties do
  desc <<~DESC
    Recompute the shared-ownership flag for all properties from description regex.

    Optional:
      BATCH_SIZE - Number of rows per batch (default: 1000)
  DESC
  task refresh_shared_ownership_flags: :environment do
    batch_size = [ENV.fetch("BATCH_SIZE", "1000").to_i, 1].max
    scope = Property.select(:id, :description, :is_shared_ownership).order(:id)
    total = Property.count

    if total.zero?
      puts "No properties found."
      next
    end

    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    processed = 0
    updated = 0
    shared_count = 0

    scope.find_in_batches(batch_size: batch_size) do |batch|
      ids_true = []
      ids_false = []

      batch.each do |property|
        processed += 1
        shared = Property.shared_ownership_from_description?(property.description)
        shared_count += 1 if shared
        next if property.is_shared_ownership == shared

        shared ? ids_true << property.id : ids_false << property.id
      end

      now = Time.current
      Property.where(id: ids_true).update_all(is_shared_ownership: true, updated_at: now) if ids_true.any?
      Property.where(id: ids_false).update_all(is_shared_ownership: false, updated_at: now) if ids_false.any?
      updated += ids_true.size + ids_false.size

      if (processed % 500).zero? || processed == total
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
        rate = elapsed.positive? ? (processed / elapsed) : processed
        puts "processed=#{processed}/#{total} updated=#{updated} shared=#{shared_count} rate=#{rate.round(1)} rows/s"
      end
    end

    puts "Done. total=#{total} updated=#{updated} shared=#{shared_count}"
  end
end
