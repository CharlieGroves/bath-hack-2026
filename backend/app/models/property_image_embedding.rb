class PropertyImageEmbedding < ApplicationRecord
  EXPECTED_DIMENSIONS = 768

  belongs_to :property

  has_neighbors :embedding_vector, dimensions: EXPECTED_DIMENSIONS

  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :source_url, presence: true
  validates :embedding_model, presence: true
  validates :fingerprint, presence: true
  validate :embedding_json_shape, if: -> { embedding.present? }

  before_validation :sync_embedding_vector_from_json
  after_commit :refresh_parent_image_embeddings_maxpool

  # @param query_vector [Array<Numeric>] 768 floats (same space as +PropertyImageEmbedder+)
  # @return ActiveRecord::Relation rows include +neighbor_distance+ (cosine distance)
  def self.nearest_to(query_vector, limit: 20, distance: "cosine")
    unless query_vector.is_a?(Array) && query_vector.size == EXPECTED_DIMENSIONS
      raise ArgumentError, "expected Array of #{EXPECTED_DIMENSIONS} floats"
    end

    nearest_neighbors(:embedding_vector, query_vector.map(&:to_f), distance: distance).limit(limit)
  end

  # Element-wise max across all non-null +embedding_vector+ rows for +property_id+ (768 floats), or +nil+ if none.
  def self.maxpool_vector_array_for_property(property_id)
    rows = where(property_id: property_id).where.not(embedding_vector: nil).order(:position).pluck(:embedding_vector)
    return nil if rows.empty?

    dim = EXPECTED_DIMENSIONS
    acc = vector_to_float_array(rows.first)
    return nil if acc.size != dim

    rows.drop(1).each do |row|
      arr = vector_to_float_array(row)
      next if arr.size != dim

      dim.times { |i| acc[i] = [acc[i], arr[i]].max }
    end
    acc
  end

  # 768 floats for ANN queries; prefers pgvector column, falls back to jsonb +embedding+ if vector not migrated yet.
  def query_vector
    if embedding_vector.present?
      v = embedding_vector
      return v.respond_to?(:to_a) ? v.to_a.map(&:to_f) : Array(v).map(&:to_f)
    end

    return unless embedding.is_a?(Array) && embedding.size == EXPECTED_DIMENSIONS

    embedding.map(&:to_f)
  end

  def self.vector_to_float_array(value)
    return [] if value.nil?

    arr = value.respond_to?(:to_a) ? value.to_a : Array(value)
    arr.map(&:to_f)
  end
  private_class_method :vector_to_float_array

  private

  def refresh_parent_image_embeddings_maxpool
    Property.refresh_image_embeddings_maxpool!(property_id)
  end

  def embedding_json_shape
    return unless embedding.is_a?(Array)

    errors.add(:embedding, "must have #{EXPECTED_DIMENSIONS} dimensions") if embedding.size != EXPECTED_DIMENSIONS
  end

  def sync_embedding_vector_from_json
    if embedding.is_a?(Array) && embedding.size == EXPECTED_DIMENSIONS
      self.embedding_vector = embedding.map(&:to_f)
    elsif embedding.blank?
      self.embedding_vector = nil
    end
  end
end
