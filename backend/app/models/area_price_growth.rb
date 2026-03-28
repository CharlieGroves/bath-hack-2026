class AreaPriceGrowth < ApplicationRecord
  has_many :properties, dependent: :nullify

  validates :area_slug, presence: true, uniqueness: true
  validates :area_name, presence: true
end
