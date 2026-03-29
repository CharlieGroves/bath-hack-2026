# k-ANN over +property_image_embeddings.embedding_vector+ (pgvector HNSW, cosine).
# Requires: +bin/rails db:migrate+ with pgvector installed, and rows backfilled / saved with +embedding_vector+ set.
class PropertyImageEmbeddingSearch
  class AnchorMissingError < StandardError; end
  class VectorMissingError < StandardError; end

  # @param property_id [Integer] anchor listing
  # @param position [Integer] which photo slot (0-based) to match
  # @param limit [Integer] max embedding rows to return (often > unique properties)
  # @param exclude_property_id [Boolean] omit the anchor property from hits
  # @return [Array<Hash>] +:property_id+, +:neighbor_distance+, +:image_position+, +:embedding_id+
  def self.similar_slots(property_id:, position:, limit: 40, exclude_property_id: true)
    anchor = PropertyImageEmbedding.find_by(property_id: property_id, position: position)
    raise AnchorMissingError, "no embedding for property #{property_id} position #{position}" unless anchor

    vec = anchor.query_vector
    raise VectorMissingError, "anchor has no queryable vector (run embedding job + pgvector migration)" if vec.blank?

    rel = PropertyImageEmbedding.nearest_to(vec, limit: limit, distance: "cosine")
    rel = rel.where.not(property_id: property_id) if exclude_property_id
    rel.map do |row|
      {
        embedding_id: row.id,
        property_id: row.property_id,
        image_position: row.position,
        neighbor_distance: row.neighbor_distance
      }
    end
  end

  # One row per property, keeping the best (lowest) distance among that property's images.
  def self.similar_properties(property_id:, position:, limit: 20, exclude_property_id: true)
    slots = similar_slots(property_id: property_id, position: position, limit: [limit * 5, 200].min, exclude_property_id: exclude_property_id)
    best = {}
    slots.each do |h|
      pid = h[:property_id]
      next if best[pid] && best[pid][:neighbor_distance] <= h[:neighbor_distance]

      best[pid] = h
    end
    best.values.sort_by { |h| h[:neighbor_distance] }.first(limit)
  end
end
