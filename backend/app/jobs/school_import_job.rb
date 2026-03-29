# Imports London KS4 schools from data/london_schools_ks4.csv, bulk-geocodes
# their postcodes via postcodes.io, and persists School records.
#
# Run once:
#   SchoolImportJob.perform_later
class SchoolImportJob < ApplicationJob
  queue_as :scraping

  CSV_PATH        = Rails.root.join("data", "london_schools_ks4.csv").freeze
  POSTCODES_IO    = "https://api.postcodes.io/postcodes".freeze
  BULK_BATCH_SIZE = 100   # postcodes.io max per bulk request

  def perform
    unless File.exist?(CSV_PATH)
      Rails.logger.error("[SchoolImportJob] CSV not found at #{CSV_PATH}")
      return
    end

    rows = CSV.read(CSV_PATH, headers: true).map(&:to_h)
    Rails.logger.info("[SchoolImportJob] Geocoding #{rows.size} schools via postcodes.io…")

    # Build postcode → {lat, lon} map via bulk requests
    postcodes   = rows.map { |r| r["postcode"] }.uniq
    coords_map  = bulk_geocode(postcodes)

    now   = Time.current
    upsert_rows = rows.map do |r|
      coords = coords_map[r["postcode"]] || {}
      {
        urn:       r["urn"],
        name:      r["name"],
        address1:  r["address1"],
        address2:  r["address2"],
        town:      r["town"],
        postcode:  r["postcode"],
        p8mea:     r["p8mea"].to_f,
        latitude:  coords[:latitude],
        longitude: coords[:longitude],
        created_at: now,
        updated_at: now
      }
    end

    School.insert_all(upsert_rows, unique_by: :urn)
    geocoded = School.geocoded.count
    Rails.logger.info("[SchoolImportJob] Imported #{School.count} schools (#{geocoded} geocoded)")
  end

  private

  def bulk_geocode(postcodes)
    result = {}
    postcodes.each_slice(BULK_BATCH_SIZE) do |batch|
      response = Faraday.post(
        POSTCODES_IO,
        { postcodes: batch }.to_json,
        "Content-Type" => "application/json",
        "Accept"       => "application/json"
      )
      next unless response.success?

      JSON.parse(response.body)["result"].each do |entry|
        next unless entry && entry["result"]
        pc  = entry["query"]
        res = entry["result"]
        result[pc] = { latitude: res["latitude"], longitude: res["longitude"] }
      end
    rescue Faraday::Error, JSON::ParserError => e
      Rails.logger.warn("[SchoolImportJob] Bulk geocode batch failed: #{e.message}")
    end
    result
  end
end
