# k-ANN over +properties.image_embeddings_maxpool_vector+ (per-listing max-pool of image vectors).
# Requires pgvector, column populated (+Property.refresh_image_embeddings_maxpool!+ / backfill task).
class PropertyImageMaxpoolSearch
  class AnchorMissingError < StandardError; end
  class VectorMissingError < StandardError; end

  # @param property_id [Integer] anchor listing
  # @param limit [Integer]
  # @param exclude_property_id [Boolean]
  # @return [Array<Hash>] +:property_id+, +:neighbor_distance+ (cosine distance on max-pool vectors)
  def self.similar_properties(property_id:, limit: 20, exclude_property_id: true)
    anchor = Property.find_by(id: property_id)
    raise AnchorMissingError, "no property #{property_id}" unless anchor

    vec = maxpool_vector_as_array(anchor.image_embeddings_maxpool_vector)
    if vec.blank?
      raise VectorMissingError,
            "property #{property_id} has no max-pool image vector (run property_image_embeddings:backfill_maxpool)"
    end

    fetch = exclude_property_id ? limit + 1 : limit
    rel = Property.nearest_by_maxpool_vector(vec, limit: fetch, distance: "cosine")
    rel = rel.where.not(id: property_id) if exclude_property_id

    rel.limit(limit).map do |row|
      { property_id: row.id, neighbor_distance: row.neighbor_distance }
    end
  end

  def self.maxpool_vector_as_array(value)
    return if value.nil?

    arr = value.respond_to?(:to_a) ? value.to_a : Array(value)
    arr = arr.map(&:to_f)
    return if arr.size != PropertyImageEmbedding::EXPECTED_DIMENSIONS

    arr
  end
end
