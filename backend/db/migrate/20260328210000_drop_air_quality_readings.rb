class DropAirQualityReadings < ActiveRecord::Migration[7.2]
  def change
    drop_table :air_quality_readings do |t|
      t.references :air_quality_station, null: false, foreign_key: true
      t.string   :pollutant,    null: false
      t.integer  :year,         null: false
      t.string   :unit
      t.decimal  :mean_value,   precision: 10, scale: 4
      t.integer  :sample_count
      t.integer  :daqi_index
      t.string   :timeseries_id
      t.timestamps
    end
  end
end
