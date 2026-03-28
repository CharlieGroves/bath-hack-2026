class EnsurePropertyImagesTableExists < ActiveRecord::Migration[7.2]
  def change
    return if table_exists?(:property_images)

    create_table :property_images do |t|
      t.references :property, null: false, foreign_key: true
      t.string :url, null: false
      t.integer :position, default: 0
      t.timestamps
    end
  end
end
