class CreatePropertyTransportSnapshots < ActiveRecord::Migration[7.2]
  def change
    create_table :property_transport_snapshots do |t|
      t.references :property, null: false, foreign_key: true, index: { unique: true }
      t.string :provider, null: false
      t.decimal :latitude, precision: 10, scale: 7, null: false
      t.decimal :longitude, precision: 10, scale: 7, null: false
      t.jsonb :flight_data, default: {}, null: false
      t.jsonb :rail_data, default: {}, null: false
      t.jsonb :road_data, default: {}, null: false
      t.datetime :fetched_at
      t.string :status, null: false, default: "pending"
      t.text :error_message

      t.timestamps
    end

    add_index :property_transport_snapshots, :status
  end
end
