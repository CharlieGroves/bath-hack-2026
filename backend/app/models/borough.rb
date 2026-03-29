class Borough < ApplicationRecord
  has_many :properties, dependent: :nullify
end
