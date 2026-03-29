# Element-wise max of all image embedding_vector rows per property (same 768-dim space as PropertyImageEmbedding).
class AddImageEmbeddingsMaxpoolVectorToProperties < ActiveRecord::Migration[7.2]
  def up
    unless pgvector_available?
      say "pgvector not installed on this system — skipping maxpool vector column."
      return
    end
    enable_extension "vector" unless extension_enabled?("vector")

    return if column_exists?(:properties, :image_embeddings_maxpool_vector)

    add_column :properties, :image_embeddings_maxpool_vector, :vector, limit: 768
  end

  def down
    remove_column :properties, :image_embeddings_maxpool_vector, if_exists: true
  end

  private

  def pgvector_available?
    return true if extension_enabled?("vector")

    raw = select_value("SELECT EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'vector')")
    ActiveModel::Type::Boolean.new.cast(raw)
  rescue ActiveRecord::StatementInvalid
    false
  end
end
