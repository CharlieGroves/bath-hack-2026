class School < ApplicationRecord
  validates :urn,      presence: true, uniqueness: true
  validates :name,     presence: true
  validates :postcode, presence: true

  scope :geocoded,     -> { where.not(latitude: nil, longitude: nil) }
  scope :not_geocoded, -> { where(latitude: nil) }
end
