# Requires PostgreSQL with the pgvector extension (https://github.com/pgvector/pgvector).
# If pgvector is not installed, this migration skips gracefully.
# To install on Ubuntu/Debian: sudo apt-get install postgresql-16-pgvector
class AddEmbeddingVectorHnswToPropertyImageEmbeddings < ActiveRecord::Migration[7.2]
  def up
    unless pgvector_available?
      say "pgvector not installed on this system — skipping. Install postgresql-16-pgvector to enable."
      return
    end
    enable_extension "vector" unless extension_enabled?("vector")

    add_column :property_image_embeddings, :embedding_vector, :vector, limit: 768

    execute <<~SQL.squish
      UPDATE property_image_embeddings AS p
      SET embedding_vector = sub.literal::vector
      FROM (
        SELECT pie.id,
               '[' || string_agg(elem::text, ',' ORDER BY ordinality) || ']' AS literal
        FROM property_image_embeddings pie,
             LATERAL jsonb_array_elements_text(pie.embedding) WITH ORDINALITY AS t(elem, ordinality)
        GROUP BY pie.id
        HAVING COUNT(*) = 768
      ) AS sub
      WHERE p.id = sub.id
    SQL

    add_index :property_image_embeddings, :embedding_vector,
              using: :hnsw,
              opclass: :vector_cosine_ops,
              name: "idx_pie_embedding_vector_hnsw"
  end

  def down
    remove_index :property_image_embeddings, name: "idx_pie_embedding_vector_hnsw", if_exists: true
    remove_column :property_image_embeddings, :embedding_vector, if_exists: true
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
