class EstateAgent < ApplicationRecord
  has_many :properties, dependent: :nullify
end
