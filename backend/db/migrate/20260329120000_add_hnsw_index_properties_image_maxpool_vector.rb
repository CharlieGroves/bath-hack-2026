class AddHnswIndexPropertiesImageMaxpoolVector < ActiveRecord::Migration[7.2]
  def up
    unless pgvector_available?
      say "pgvector not installed on this system — skipping maxpool hnsw index."
      return
    end
    enable_extension "vector" unless extension_enabled?("vector")

    return unless column_exists?(:properties, :image_embeddings_maxpool_vector)
    return if index_exists?(:properties, :image_embeddings_maxpool_vector, name: "idx_properties_image_maxpool_vector_hnsw")

    add_index :properties, :image_embeddings_maxpool_vector,
              using: :hnsw,
              opclass: :vector_cosine_ops,
              name: "idx_properties_image_maxpool_vector_hnsw"
  end

  def down
    remove_index :properties, name: "idx_properties_image_maxpool_vector_hnsw", if_exists: true
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
