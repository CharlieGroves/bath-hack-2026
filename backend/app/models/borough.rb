class Borough < ApplicationRecord
  has_many :properties, dependent: :nullify

  validates :name,      presence: true, uniqueness: true
  validates :nte_score, presence: true,
                        numericality: { greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0 }
end
