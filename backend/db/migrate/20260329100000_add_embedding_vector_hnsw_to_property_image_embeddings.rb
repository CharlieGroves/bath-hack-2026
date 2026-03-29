# Requires PostgreSQL with the pgvector extension (https://github.com/pgvector/pgvector).
# macOS: brew install pgvector && ensure the server loads it, or use an image that includes it.
class AddEmbeddingVectorHnswToPropertyImageEmbeddings < ActiveRecord::Migration[7.2]
  def up
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
    remove_index :property_image_embeddings, name: "idx_pie_embedding_vector_hnsw"
    remove_column :property_image_embeddings, :embedding_vector
  end
end
