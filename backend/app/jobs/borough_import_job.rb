# Populates the boroughs table from data/borough_nte_scores.csv, then
# enqueues BoroughBackfillJob to assign existing properties.
#
# Run once:
#   BoroughImportJob.perform_later
class BoroughImportJob < ApplicationJob
  queue_as :scraping

  CSV_PATH = Rails.root.join("data", "borough_nte_scores.csv").freeze

  def perform
    unless File.exist?(CSV_PATH)
      Rails.logger.error("[BoroughImportJob] CSV not found at #{CSV_PATH}")
      return
    end

    Rails.logger.info("[BoroughImportJob] Importing borough NTE scores…")

    now   = Time.current
    rows  = []

    CSV.foreach(CSV_PATH, headers: true) do |row|
      rows << {
        name:          row["name"],
        nte_score_raw: row["nte_score_raw"].to_f,
        nte_score:     row["nte_score"].to_f,
        created_at:    now,
        updated_at:    now
      }
    end

    Borough.insert_all(rows, unique_by: :name)
    Rails.logger.info("[BoroughImportJob] Upserted #{Borough.count} boroughs. Backfilling properties…")

    BoroughBackfillJob.perform_later
  end
end
