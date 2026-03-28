class CreateAirQualityReadings < ActiveRecord::Migration[7.2]
  def change
    create_table :air_quality_readings do |t|
      t.references :air_quality_station, null: false, foreign_key: true

      # One row per station / pollutant / year
      t.string   :pollutant,    null: false   # "NO2", "O3", "PM2.5", "PM10", "SO2"
      t.integer  :year,         null: false   # 2023, 2024, 2025
      t.string   :unit                        # "µg/m³" etc. from API uom field

      # Annual mean computed from hourly observations (sentinel −99 values excluded)
      t.decimal  :mean_value,   precision: 10, scale: 4
      t.integer  :sample_count  # number of valid hourly readings that went into the mean

      # DAQI index (1–10) for this pollutant × year combination
      t.integer  :daqi_index

      # The DEFRA timeseries numeric ID this data was pulled from
      t.string   :timeseries_id

      t.timestamps
    end

    add_index :air_quality_readings, [:air_quality_station_id, :pollutant, :year],
              unique: true,
              name: "index_aq_readings_on_station_pollutant_year"
    add_index :air_quality_readings, :pollutant
    add_index :air_quality_readings, :year
  end
end
