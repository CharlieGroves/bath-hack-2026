class RenameEmbeddingModelNameColumns < ActiveRecord::Migration[7.2]
  def change
    rename_column :property_description_embeddings, :model_name, :embedding_model
    rename_column :property_image_embeddings, :model_name, :embedding_model
  end
end
