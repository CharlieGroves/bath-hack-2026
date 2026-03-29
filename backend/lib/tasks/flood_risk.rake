namespace :flood_risk do
  desc "Import flood risk datapoints from backend/data/flood_risk_datapoints.csv"
  task import: :environment do
    csv_path = Rails.root.join("data", "flood_risk_datapoints.csv")
    abort "CSV not found at #{csv_path}" unless File.exist?(csv_path)

    puts "Importing flood risk datapoints from #{csv_path}…"

    rows = []
    now  = Time.current

    CSV.foreach(csv_path, headers: true) do |row|
      rows << {
        latitude:   row["latitude"].to_f,
        longitude:  row["longitude"].to_f,
        risk_level: row["risk_level"],
        risk_band:  row["risk_band"].to_i,
        created_at: now,
        updated_at: now
      }

      # Insert in batches of 1000 to avoid huge single INSERT
      if rows.size >= 1_000
        FloodRiskDatapoint.insert_all(rows)
        rows = []
        print "."
      end
    end

    FloodRiskDatapoint.insert_all(rows) if rows.any?
    puts "\nDone. Total: #{FloodRiskDatapoint.count} datapoints."
  end
end
