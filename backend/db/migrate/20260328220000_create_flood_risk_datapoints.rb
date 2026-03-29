class CreateFloodRiskDatapoints < ActiveRecord::Migration[7.2]
  def change
    create_table :flood_risk_datapoints do |t|
      t.decimal :latitude,   precision: 10, scale: 7, null: false
      t.decimal :longitude,  precision: 10, scale: 7, null: false

      # "High", "Medium", "Low", "Very Low"  (PROB_4BAND from RoFRS dataset)
      t.string  :risk_level, null: false

      # Numeric band: 4=High, 3=Medium, 2=Low, 1=Very Low — for sorting/filtering
      t.integer :risk_band,  null: false

      t.timestamps
    end

    add_index :flood_risk_datapoints, [:latitude, :longitude]
    add_index :flood_risk_datapoints, :risk_band
  end
end
