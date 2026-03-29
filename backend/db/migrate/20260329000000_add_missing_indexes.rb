class AddMissingIndexes < ActiveRecord::Migration[7.2]
  def change
    add_index :property_nearest_stations, :distance_miles
    add_index :property_nearest_stations, :walking_minutes
    add_index :air_quality_stations, :daqi_index
    add_index :property_crime_snapshots, [:status, :fetched_at]
    add_index :properties, [:status, :property_type, :price_pence]
    add_index :properties, [:latitude, :longitude, :price_per_sqft_pence],
      where: "latitude IS NOT NULL AND longitude IS NOT NULL AND price_per_sqft_pence IS NOT NULL"
  end
end
