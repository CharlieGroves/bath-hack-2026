class CreateAssociatedPropertyTables < ActiveRecord::Migration[7.2]
  def change
    create_table :property_enrichments do |t|
      t.references :property, null: false, foreign_key: true
      t.string  :nearest_station_name
      t.decimal :distance_to_station_km, precision: 6, scale: 3
      t.string  :crime_rate_category
      t.string  :flood_risk
      t.string  :nearest_school_ofsted
      t.datetime :enriched_at
      t.timestamps
    end

    create_table :property_embeddings do |t|
      t.references :property, null: false, foreign_key: true
      t.text :embedding
      t.datetime :embedded_at
      t.timestamps
    end

    create_table :property_images do |t|
      t.references :property, null: false, foreign_key: true
      t.string  :url, null: false
      t.integer :position, default: 0
      t.timestamps
    end
  end
end
