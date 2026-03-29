class PropertyImageEmbedding < ApplicationRecord
  EXPECTED_DIMENSIONS = 768

  belongs_to :property

  has_neighbors :embedding_vector, dimensions: EXPECTED_DIMENSIONS

  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :source_url, presence: true
  validates :embedding_model, presence: true
  validates :fingerprint, presence: true
  validate :embedding_json_shape, if: -> { embedding.present? }

  # @param query_vector [Array<Numeric>] 768 floats (same space as +PropertyImageEmbedder+)
  # @return ActiveRecord::Relation rows include +neighbor_distance+ (cosine distance)
  def self.nearest_to(query_vector, limit: 20, distance: "cosine")
    unless query_vector.is_a?(Array) && query_vector.size == EXPECTED_DIMENSIONS
      raise ArgumentError, "expected Array of #{EXPECTED_DIMENSIONS} floats"
    end

    nearest_neighbors(:embedding_vector, query_vector.map(&:to_f), distance: distance).limit(limit)
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

  private

  def embedding_json_shape
    return unless embedding.is_a?(Array)

    errors.add(:embedding, "must have #{EXPECTED_DIMENSIONS} dimensions") if embedding.size != EXPECTED_DIMENSIONS
  end

  before_validation :sync_embedding_vector_from_json

  def sync_embedding_vector_from_json
    if embedding.is_a?(Array) && embedding.size == EXPECTED_DIMENSIONS
      self.embedding_vector = embedding.map(&:to_f)
    elsif embedding.blank?
      self.embedding_vector = nil
    end
  end
end
