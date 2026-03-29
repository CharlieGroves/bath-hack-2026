class CreatePropertyImageEmbeddings < ActiveRecord::Migration[7.2]
  def change
    return if table_exists?(:property_image_embeddings)

    create_table :property_image_embeddings do |t|
      t.references :property, null: false, foreign_key: true
      t.integer :position, null: false
      t.text :source_url, null: false
      t.jsonb :embedding, null: false, default: []
      t.string :model_name, null: false
      t.string :fingerprint, null: false

      t.timestamps
    end

    add_index :property_image_embeddings, %i[property_id position], unique: true, name: "index_property_image_embeddings_on_property_and_position"
  end
end
