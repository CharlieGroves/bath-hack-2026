class AddMissingIndexes < ActiveRecord::Migration[7.2]
  def change
    unless index_exists?(:property_nearest_stations, :distance_miles)
      add_index :property_nearest_stations, :distance_miles
    end
    unless index_exists?(:property_nearest_stations, :walking_minutes)
      add_index :property_nearest_stations, :walking_minutes
    end
    unless index_exists?(:air_quality_stations, :daqi_index)
      add_index :air_quality_stations, :daqi_index
    end
    unless index_exists?(:property_crime_snapshots, [:status, :fetched_at])
      add_index :property_crime_snapshots, [:status, :fetched_at]
    end
    unless index_exists?(:properties, [:status, :property_type, :price_pence])
      add_index :properties, [:status, :property_type, :price_pence]
    end

    geo_partial_opts = {
      where: "latitude IS NOT NULL AND longitude IS NOT NULL AND price_per_sqft_pence IS NOT NULL"
    }
    unless index_exists?(:properties, [:latitude, :longitude, :price_per_sqft_pence], **geo_partial_opts)
      add_index :properties, [:latitude, :longitude, :price_per_sqft_pence], **geo_partial_opts
    end
  end
end
