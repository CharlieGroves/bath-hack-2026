class PropertyMonthlyBillEstimate < ApplicationRecord
  STATUSES = %w[pending ready failed].freeze
  CONFIDENCE_LEVELS = %w[low medium high].freeze

  belongs_to :property

  validates :property_id, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :confidence, inclusion: { in: CONFIDENCE_LEVELS }, allow_nil: true
end
