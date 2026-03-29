namespace :ml do
  desc <<~DESC
    Enrich properties with monthly-bill estimates from OpenAI.

    Optional:
      ONLY_MISSING - 1 to process only properties without ready estimates (default: 1)
      RUN_NOW      - 1 to perform synchronously (default: 0 enqueue jobs)
      BATCH_SIZE   - Batch size for iteration (default: 100)
      START_ID     - Minimum property id (inclusive)
      END_ID       - Maximum property id (inclusive)
  DESC
  task enrich_monthly_bills: :environment do
    bool = ActiveModel::Type::Boolean.new
    only_missing = bool.cast(ENV.fetch("ONLY_MISSING", "1"))
    run_now = bool.cast(ENV.fetch("RUN_NOW", "0"))
    batch_size = [ENV.fetch("BATCH_SIZE", "100").to_i, 1].max

    scope = Property.order(:id)
    scope = scope.where("id >= ?", ENV["START_ID"].to_i) if ENV["START_ID"].present?
    scope = scope.where("id <= ?", ENV["END_ID"].to_i) if ENV["END_ID"].present?
    if only_missing
      scope = scope
        .left_joins(:property_monthly_bill_estimate)
        .where("property_monthly_bill_estimates.id IS NULL OR property_monthly_bill_estimates.status <> ?", "ready")
    end

    total = scope.count
    puts "Monthly bills enrichment scope: #{total} properties"
    next if total.zero?

    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    processed = 0
    errors = 0

    scope.find_in_batches(batch_size: batch_size) do |batch|
      batch.each do |property|
        begin
          run_now ? PropertyMonthlyBillEstimateJob.perform_now(property.id) : PropertyMonthlyBillEstimateJob.perform_later(property.id)
        rescue StandardError => e
          errors += 1
          Rails.logger.warn("[ml:enrich_monthly_bills] property=#{property.id} error=#{e.class}: #{e.message}")
        ensure
          processed += 1
        end
      end

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
      rate = elapsed.positive? ? (processed / elapsed) : processed
      puts "processed=#{processed}/#{total} errors=#{errors} rate=#{rate.round(1)} props/s"
    end

    mode = run_now ? "synchronous" : "enqueued"
    puts "Monthly bills enrichment complete (#{mode}). processed=#{processed} errors=#{errors}"
  end
end
