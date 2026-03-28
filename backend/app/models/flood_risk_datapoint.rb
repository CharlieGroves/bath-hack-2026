class FloodRiskDatapoint < ApplicationRecord
  has_many :properties, dependent: :nullify

  RISK_LEVELS = ["Very Low", "Low", "Medium", "High"].freeze

  validates :latitude,   presence: true
  validates :longitude,  presence: true
  validates :risk_level, presence: true, inclusion: { in: RISK_LEVELS }
  validates :risk_band,  presence: true, inclusion: { in: 1..4 }
end
