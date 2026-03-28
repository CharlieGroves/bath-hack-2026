class PropertyTransportSnapshot < ApplicationRecord
  STATUSES = %w[pending ready failed].freeze

  belongs_to :property

  validates :property_id, uniqueness: true
  validates :provider, presence: true
  validates :status, inclusion: { in: STATUSES }
end
