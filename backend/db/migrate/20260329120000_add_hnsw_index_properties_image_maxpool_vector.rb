class AddHnswIndexPropertiesImageMaxpoolVector < ActiveRecord::Migration[7.2]
  def change
    add_index :properties, :image_embeddings_maxpool_vector,
              using: :hnsw,
              opclass: :vector_cosine_ops,
              name: "idx_properties_image_maxpool_vector_hnsw"
  end
end
