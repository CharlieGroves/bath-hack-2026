# Populates the boroughs table from:
#   data/borough_nte_scores.csv       — night-time economy scores
#   data/borough_wellbeing_scores.csv — life satisfaction, happiness, anxiety
#
# Then enqueues BoroughBackfillJob to assign existing properties.
#
# Run once:
#   BoroughImportJob.perform_later
class BoroughImportJob < ApplicationJob
  queue_as :scraping

  NTE_CSV       = Rails.root.join("data", "borough_nte_scores.csv").freeze
  WELLBEING_CSV = Rails.root.join("data", "borough_wellbeing_scores.csv").freeze

  def perform
    [NTE_CSV, WELLBEING_CSV].each do |path|
      unless File.exist?(path)
        Rails.logger.error("[BoroughImportJob] CSV not found at #{path}")
        return
      end
    end

    Rails.logger.info("[BoroughImportJob] Importing borough scores…")

    now = Time.current

    # Seed from NTE CSV (establishes rows with unique name)
    nte_rows = []
    CSV.foreach(NTE_CSV, headers: true) do |row|
      nte_rows << {
        name:          row["name"],
        nte_score_raw: row["nte_score_raw"].to_f,
        nte_score:     row["nte_score"].to_f,
        created_at:    now,
        updated_at:    now
      }
    end
    Borough.insert_all(nte_rows, unique_by: :name)

    # Merge wellbeing scores by name
    CSV.foreach(WELLBEING_CSV, headers: true) do |row|
      Borough.where(name: row["name"]).update_all(
        life_satisfaction_score_raw: row["life_satisfaction_score_raw"].presence&.to_f,
        life_satisfaction_score:     row["life_satisfaction_score"].presence&.to_f,
        happiness_score_raw:         row["happiness_score_raw"].presence&.to_f,
        happiness_score:             row["happiness_score"].presence&.to_f,
        anxiety_score_raw:           row["anxiety_score_raw"].presence&.to_f,
        anxiety_score:               row["anxiety_score"].presence&.to_f
      )
    end

    Rails.logger.info("[BoroughImportJob] Imported #{Borough.count} boroughs. Backfilling properties…")
    BoroughBackfillJob.perform_later
  end
end
