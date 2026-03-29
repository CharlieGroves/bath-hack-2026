module PropertyImageEmbeddingsTaskHelpers
  module_function

  def image_embeddings_up_to_date?(property, urls)
    return false if property.property_image_embeddings.count != urls.length

    urls.each_with_index do |url, position|
      fp = PropertyImageEmbedder.fingerprint_for_slot(position, url)
      rec = property.property_image_embeddings.find_by(position: position)
      return false if rec.nil? || rec.fingerprint != fp
      return false unless rec.embedding.is_a?(Array) && rec.embedding.size == PropertyImageEmbedder::EXPECTED_DIM
      return false unless rec.embedding_vector.present?
    end

    true
  end
end

namespace :property_image_embeddings do
  desc <<~DESC.squish
    Enqueue PropertyImageEmbedJob for properties that have photo_urls but need embeddings
    (missing rows, wrong count vs photos, or stale fingerprint per slot). Requires Sidekiq (scraping queue).
  DESC
  task backfill: :environment do
    enqueued = 0
    Property.includes(:property_image_embeddings).find_each do |property|
      urls = Array(property.photo_urls).map(&:to_s).map(&:strip).reject(&:blank?)
      next if urls.empty?

      next if PropertyImageEmbeddingsTaskHelpers.image_embeddings_up_to_date?(property, urls)

      PropertyImageEmbedJob.perform_later(property.id)
      enqueued += 1
    end
    puts "Enqueued #{enqueued} image embedding job(s)."
  end

  desc "Enqueue image embedding for every property with at least one photo URL"
  task backfill_force: :environment do
    enqueued = 0
    Property.find_each do |property|
      urls = Array(property.photo_urls).map(&:to_s).map(&:strip).reject(&:blank?)
      next if urls.empty?

      PropertyImageEmbedJob.perform_later(property.id)
      enqueued += 1
    end
    puts "Enqueued #{enqueued} image embedding job(s)."
  end

  desc "Recompute properties.image_embeddings_maxpool_vector from image embedding rows (no Sidekiq)"
  task backfill_maxpool: :environment do
    pids = PropertyImageEmbedding.where.not(embedding_vector: nil).distinct.pluck(:property_id)
    pids.each { |id| Property.refresh_image_embeddings_maxpool!(id) }
    puts "Updated maxpool vector for #{pids.size} propert#{pids.size == 1 ? 'y' : 'ies'}."
  end
end

namespace :property_embeddings do
  desc <<~DESC.squish
    Enqueue PropertyDescriptionEmbedJob for every property with a non-blank description
    that has no embedding or whose stored fingerprint no longer matches the description.
    Use this after adding embeddings for already-imported listings. Requires Sidekiq (scraping queue).
  DESC
  task backfill: :environment do
    enqueued = 0
    Property.includes(:property_description_embedding).where.not(description: [nil, ""]).find_each do |property|
      fp = PropertyDescriptionEmbedder.fingerprint_for(property.description)
      next if property.property_description_embedding&.fingerprint == fp

      PropertyDescriptionEmbedJob.perform_later(property.id)
      enqueued += 1
    end
    puts "Enqueued #{enqueued} embedding job(s)."
  end

  desc "Enqueue embedding jobs for all properties with a description, even if already up to date"
  task backfill_force: :environment do
    enqueued = 0
    Property.where.not(description: [nil, ""]).find_each do |property|
      PropertyDescriptionEmbedJob.perform_later(property.id)
      enqueued += 1
    end
    puts "Enqueued #{enqueued} embedding job(s)."
  end
end
