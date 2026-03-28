class AddFloodRiskDatapointToProperties < ActiveRecord::Migration[7.2]
  def change
    add_reference :properties, :flood_risk_datapoint,
                  null: true,
                  foreign_key: true,
                  index: true
  end
end
