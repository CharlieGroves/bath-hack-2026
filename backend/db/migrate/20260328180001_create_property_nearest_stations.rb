class CreatePropertyNearestStations < ActiveRecord::Migration[7.2]
  def change
    create_table :property_nearest_stations do |t|
      t.references :property, null: false, foreign_key: true, index: true
      t.string  :name,           null: false
      t.decimal :distance_miles, precision: 5, scale: 2
      t.string  :transport_type
      t.integer :walking_minutes

      t.timestamps
    end
  end
end
