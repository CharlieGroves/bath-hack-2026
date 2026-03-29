class PropertyDescriptionEmbedding < ApplicationRecord
  belongs_to :property

  validates :embedding_model, presence: true
  validates :fingerprint, presence: true
  validate :embedding_vector_shape, if: -> { embedding.present? }

  EXPECTED_DIMENSIONS = 768

  private

  def embedding_vector_shape
    return unless embedding.is_a?(Array)

    errors.add(:embedding, "must have #{EXPECTED_DIMENSIONS} dimensions") if embedding.size != EXPECTED_DIMENSIONS
  end
end
