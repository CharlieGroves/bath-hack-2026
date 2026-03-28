class CreateAirQualityStations < ActiveRecord::Migration[7.2]
  def change
    create_table :air_quality_stations do |t|
      # DEFRA numeric station ID (properties.id from the SOS REST API)
      t.integer  :external_id,         null: false
      t.string   :name,                null: false

      t.decimal  :latitude,            precision: 10, scale: 7, null: false
      t.decimal  :longitude,           precision: 10, scale: 7, null: false

      # Computed DAQI composite (1–10, max across pollutants)
      t.integer  :daqi_index
      t.string   :daqi_band           # "Low" / "Moderate" / "High" / "Very High"

      # When readings were last successfully ingested
      t.datetime :readings_fetched_at

      t.timestamps
    end

    add_index :air_quality_stations, :external_id, unique: true
    add_index :air_quality_stations, [:latitude, :longitude]
  end
end
