class AddAirQualityStationToProperties < ActiveRecord::Migration[7.2]
  def change
    add_reference :properties, :air_quality_station,
                  null: true,
                  foreign_key: true,
                  index: true
  end
end
