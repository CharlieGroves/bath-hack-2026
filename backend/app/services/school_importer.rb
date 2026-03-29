require "csv"

class SchoolImporter
  DEFAULT_PATH = Rails.root.join("data", "london_schools_ks4.csv")

  def initialize(csv_path: DEFAULT_PATH)
    @csv_path = Pathname.new(csv_path)
  end

  def call
    rows = []

    CSV.foreach(@csv_path, headers: true) do |row|
      rows << {
        urn:      row.fetch("urn").to_s.strip,
        name:     row.fetch("name").to_s.strip,
        address1: row["address1"].presence,
        address2: row["address2"].presence,
        town:     row["town"].presence,
        postcode: row.fetch("postcode").to_s.strip,
        p8mea:    row["p8mea"].presence&.to_f,
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    School.upsert_all(rows, unique_by: :index_schools_on_urn, update_only: %i[name address1 address2 town postcode p8mea])

    rows.size
  end
end
