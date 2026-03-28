class EstateAgent < ApplicationRecord
  has_many :properties, dependent: :nullify

  validates :lookup_key, presence: true, uniqueness: true
  validates :google_place_id, presence: true, uniqueness: true
end
