# Imports flood risk datapoints from data/flood_risk_datapoints.csv, then
# backfills all existing properties that don't yet have an assignment.
#
# Run once after deploying:
#   FloodRiskImportJob.perform_later
class FloodRiskImportJob < ApplicationJob
  queue_as :scraping

  def perform
    csv_path = Rails.root.join("data", "flood_risk_datapoints.csv")
    unless File.exist?(csv_path)
      Rails.logger.error("[FloodRiskImportJob] CSV not found at #{csv_path}")
      return
    end

    Rails.logger.info("[FloodRiskImportJob] Importing flood risk datapoints…")

    rows = []
    now  = Time.current
    total = 0

    CSV.foreach(csv_path, headers: true) do |row|
      rows << {
        latitude:   row["latitude"].to_f,
        longitude:  row["longitude"].to_f,
        risk_level: row["risk_level"],
        risk_band:  row["risk_band"].to_i,
        created_at: now,
        updated_at: now
      }

      if rows.size >= 1_000
        FloodRiskDatapoint.insert_all(rows)
        total += rows.size
        rows = []
      end
    end

    if rows.any?
      FloodRiskDatapoint.insert_all(rows)
      total += rows.size
    end

    Rails.logger.info("[FloodRiskImportJob] Imported #{total} datapoints. Backfilling properties…")

    FloodRiskBackfillJob.perform_later
  end
end
