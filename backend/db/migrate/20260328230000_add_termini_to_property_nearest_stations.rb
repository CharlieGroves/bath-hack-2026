class AddTerminiToPropertyNearestStations < ActiveRecord::Migration[7.2]
  def change
    add_column :property_nearest_stations, :termini, :string, array: true, default: []
  end
end
