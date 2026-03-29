# Element-wise max of all image embedding_vector rows per property (same 768-dim space as PropertyImageEmbedding).
class AddImageEmbeddingsMaxpoolVectorToProperties < ActiveRecord::Migration[7.2]
  def change
    add_column :properties, :image_embeddings_maxpool_vector, :vector, limit: 768
  end
end
