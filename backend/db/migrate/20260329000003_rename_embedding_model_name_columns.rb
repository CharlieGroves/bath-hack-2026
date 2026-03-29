class RenameEmbeddingModelNameColumns < ActiveRecord::Migration[7.2]
  def change
    if table_exists?(:property_description_embeddings) &&
       column_exists?(:property_description_embeddings, :model_name)
      rename_column :property_description_embeddings, :model_name, :embedding_model
    end

    if table_exists?(:property_image_embeddings) &&
       column_exists?(:property_image_embeddings, :model_name)
      rename_column :property_image_embeddings, :model_name, :embedding_model
    end
  end
end
