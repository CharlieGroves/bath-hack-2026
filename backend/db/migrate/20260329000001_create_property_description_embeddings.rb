class CreatePropertyDescriptionEmbeddings < ActiveRecord::Migration[7.2]
  def change
    return if table_exists?(:property_description_embeddings)

    create_table :property_description_embeddings do |t|
      t.references :property, null: false, foreign_key: true, index: { unique: true }
      t.jsonb :embedding, null: false, default: []
      t.string :model_name, null: false
      t.string :fingerprint, null: false

      t.timestamps
    end
  end
end
