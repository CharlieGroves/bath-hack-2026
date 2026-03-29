# Re-ranks image k-ANN candidates using description embeddings (MiniLM / +PropertyDescriptionEmbedder+)
# vs a query string embedding. Image vectors (DINOv2) and text vectors live in different spaces — only the text side compares
# query text to stored +property_description_embeddings+; image scores come from the ANN pass unchanged.
class PropertyHybridImageTextRanking
  # Cosine distance is in [0, 2] for typical numeric vectors; use upper bound when a listing has no description embedding.
  MISSING_DESCRIPTION_DISTANCE = 2.0

  # @param text_weight [Float] in [0, 1]; image weight is +1 - text_weight+
  # @param candidate_limit [Integer] how many distinct properties to pull from image ANN before re-ranking
  # @return [Array<Hash>] same keys as image search hits plus +:description_query_distance+, +:hybrid_distance+
  def self.for_per_image(property_id:, position:, text_query:, limit:, text_weight: 0.35,
                         exclude_property_id: true, candidate_limit: nil)
    w_txt = text_weight.to_f.clamp(0.0, 1.0)
    w_img = 1.0 - w_txt
    pool = candidate_limit || [[limit * 8, 200].max, 400].min

    slots = PropertyImageEmbeddingSearch.similar_slots(
      property_id: property_id,
      position: position,
      limit: pool,
      exclude_property_id: exclude_property_id
    )
    by_property = best_image_hit_per_property(slots)
    candidates = by_property.values
    return [] if candidates.empty?

    if w_txt <= 0.0
      return candidates.sort_by { |h| h[:neighbor_distance] }.first(limit)
    end

    query_vec = PropertyDescriptionEmbedder.embed_text!(text_query)
    score_candidates(candidates, query_vec, limit:, w_img:, w_txt:)
  end

  # @see .for_per_image
  def self.for_maxpool(property_id:, text_query:, limit:, text_weight: 0.35,
                       exclude_property_id: true, candidate_limit: nil)
    w_txt = text_weight.to_f.clamp(0.0, 1.0)
    w_img = 1.0 - w_txt
    pool = candidate_limit || [[limit * 8, 200].max, 400].min

    anchor = Property.find_by(id: property_id)
    raise PropertyImageMaxpoolSearch::AnchorMissingError, "no property #{property_id}" unless anchor

    vec = PropertyImageMaxpoolSearch.maxpool_vector_as_array(anchor.image_embeddings_maxpool_vector)
    if vec.blank?
      raise PropertyImageMaxpoolSearch::VectorMissingError,
            "property #{property_id} has no max-pool image vector (run property_image_embeddings:backfill_maxpool)"
    end

    fetch = exclude_property_id ? pool + 1 : pool
    rel = Property.nearest_by_maxpool_vector(vec, limit: fetch, distance: "cosine")
    rel = rel.where.not(id: property_id) if exclude_property_id
    candidates = rel.limit(pool).map do |row|
      { property_id: row.id, neighbor_distance: row.neighbor_distance }
    end

    return [] if candidates.empty?

    if w_txt <= 0.0
      return candidates.sort_by { |h| h[:neighbor_distance] }.first(limit)
    end

    query_vec = PropertyDescriptionEmbedder.embed_text!(text_query)
    score_candidates(candidates, query_vec, limit:, w_img:, w_txt:)
  end

  def self.cosine_distance(a, b)
    dim = PropertyDescriptionEmbedding::EXPECTED_DIMENSIONS
    raise ArgumentError, "expected #{dim}-dim vectors" unless a.size == dim && b.size == dim

    dot = 0.0
    na = 0.0
    nb = 0.0
    dim.times do |i|
      x = a[i].to_f
      y = b[i].to_f
      dot += x * y
      na += x * x
      nb += y * y
    end
    denom = Math.sqrt(na) * Math.sqrt(nb)
    return 1.0 if denom.zero?

    1.0 - (dot / denom)
  end

  def self.best_image_hit_per_property(slots)
    best = {}
    slots.each do |h|
      pid = h[:property_id]
      cur = best[pid]
      next if cur && cur[:neighbor_distance] <= h[:neighbor_distance]

      best[pid] = h
    end
    best
  end

  def self.score_candidates(candidates, query_vec, limit:, w_img:, w_txt:)
    pids = candidates.map { |h| h[:property_id] }
    desc_by_pid = PropertyDescriptionEmbedding.where(property_id: pids).index_by(&:property_id)

    img_dists = candidates.to_h { |h| [h[:property_id], h[:neighbor_distance].to_f] }
    txt_dists = pids.to_h do |pid|
      rec = desc_by_pid[pid]
      emb = rec&.embedding
      d =
        if emb.is_a?(Array) && emb.size == PropertyDescriptionEmbedding::EXPECTED_DIMENSIONS
          cosine_distance(query_vec, emb)
        else
          MISSING_DESCRIPTION_DISTANCE
        end
      [pid, d]
    end

    n_img = min_max_normalize(img_dists)
    n_txt = min_max_normalize(txt_dists)

    scored = candidates.map do |h|
      pid = h[:property_id]
      hybrid = w_img * n_img[pid] + w_txt * n_txt[pid]
      h.merge(
        description_query_distance: txt_dists[pid],
        hybrid_distance: hybrid
      )
    end

    scored.sort_by! { |h| h[:hybrid_distance] }
    scored.first(limit)
  end

  def self.min_max_normalize(by_id)
    vals = by_id.values
    return by_id.keys.to_h { |k| [k, 0.0] } if vals.empty?

    min = vals.min
    max = vals.max
    span = max - min
    if span < 1e-12
      return by_id.keys.to_h { |k| [k, 0.0] }
    end

    by_id.transform_values { |v| (v - min) / span }
  end
end
