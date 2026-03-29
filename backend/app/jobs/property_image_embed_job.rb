class PropertyImageEmbedJob < ApplicationJob
  queue_as :scraping

  def perform(property_id)
    property = Property.find_by(id: property_id)
    return unless property

    urls = normalize_photo_urls(property)
    if urls.empty?
      property.property_image_embeddings.destroy_all
      return
    end

    property.property_image_embeddings.where("position >= ?", urls.length).destroy_all

    existing_by_position = property.property_image_embeddings.index_by(&:position)
    needed_indices = urls.each_with_index.filter_map do |url, position|
      fp = PropertyImageEmbedder.fingerprint_for_slot(position, url)
      rec = existing_by_position[position]
      next nil if rec&.fingerprint == fp &&
        rec.embedding.is_a?(Array) && rec.embedding.size == PropertyImageEmbedder::EXPECTED_DIM &&
        rec.embedding_vector.present?

      position
    end

    if needed_indices.empty?
      return
    end

    payload_urls = needed_indices.map { |i| urls[i] }
    vectors = PropertyImageEmbedder.embed_urls!(payload_urls)

    PropertyImageEmbedding.transaction do
      needed_indices.each_with_index do |position, idx|
        vec = vectors[idx]
        url = urls[position]
        fp = PropertyImageEmbedder.fingerprint_for_slot(position, url)

        if vec.nil?
          property.property_image_embeddings.where(position: position).destroy_all
          next
        end

        rec = existing_by_position[position] || property.property_image_embeddings.build(position: position)
        rec.assign_attributes(
          source_url: url,
          embedding: vec,
          embedding_model: PropertyImageEmbedder::MODEL_ID,
          fingerprint: fp
        )
        rec.save!
      end
    end
  rescue PropertyImageEmbedder::Error => e
    Rails.logger.warn("[PropertyImageEmbedJob] property=#{property_id}: #{e.message}")
  end

  private

  def normalize_photo_urls(property)
    Array(property.photo_urls).map(&:to_s).map(&:strip).reject(&:blank?)
  end
end
