class PropertyDescriptionEmbedJob < ApplicationJob
  queue_as :scraping

  def perform(property_id)
    property = Property.find_by(id: property_id)
    return unless property

    if property.description.blank?
      property.property_description_embedding&.destroy
      return
    end

    fp = PropertyDescriptionEmbedder.fingerprint_for(property.description)
    existing = property.property_description_embedding
    return if existing&.fingerprint == fp

    vector = PropertyDescriptionEmbedder.embed_text!(property.description)

    record = existing || property.build_property_description_embedding
    record.assign_attributes(
      embedding: vector,
      embedding_model: PropertyDescriptionEmbedder::MODEL_ID,
      fingerprint: fp
    )
    record.save!
  rescue PropertyDescriptionEmbedder::Error => e
    Rails.logger.warn("[PropertyDescriptionEmbedJob] property=#{property_id}: #{e.message}")
  end
end
