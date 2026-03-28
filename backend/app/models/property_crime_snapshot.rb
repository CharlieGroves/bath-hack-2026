class PropertyCrimeSnapshot < ApplicationRecord
  belongs_to :property

  STATUSES = %w[pending ready failed].freeze

  validates :status, inclusion: { in: STATUSES }
end
