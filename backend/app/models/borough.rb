class Borough < ApplicationRecord
  has_many :properties, dependent: :nullify

  validates :name,      presence: true, uniqueness: true
  validates :nte_score, presence: true,
                        numericality: { greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0 }

  # Wellbeing scores are optional (City of London has no data)
  validates :life_satisfaction_score, numericality: { in: 0.0..1.0 }, allow_nil: true
  validates :happiness_score,         numericality: { in: 0.0..1.0 }, allow_nil: true
  validates :anxiety_score,           numericality: { in: 0.0..1.0 }, allow_nil: true
end
