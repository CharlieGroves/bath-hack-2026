class Property < ApplicationRecord
  extend FriendlyId
  friendly_id :rightmove_id, use: :slugged

  has_one  :property_enrichment, dependent: :destroy
  has_one  :property_embedding,  dependent: :destroy
  has_many :property_images,     dependent: :destroy

  STATUSES       = %w[active under_offer sold let].freeze
  PROPERTY_TYPES = %w[flat terraced semi_detached detached bungalow land other].freeze
  TENURES        = %w[freehold leasehold share_of_freehold].freeze
  EPC_RATINGS    = %w[A B C D E F G].freeze
  COUNCIL_BANDS  = %w[A B C D E F G H].freeze

  validates :rightmove_id, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  scope :active,        -> { where(status: "active") }
  scope :for_sale,      -> { where.not(status: %w[let]) }
  scope :by_newest,     -> { order(listed_at: :desc) }
  scope :by_price_asc,  -> { order(price_pence: :asc) }
  scope :by_price_desc, -> { order(price_pence: :desc) }

  scope :with_enrichment, -> { joins(:property_enrichment) }

  # Classical filter scopes — used by PropertySearch service
  scope :min_price,    ->(p) { where("price_pence >= ?", p) }
  scope :max_price,    ->(p) { where("price_pence <= ?", p) }
  scope :min_beds,     ->(n) { where("bedrooms >= ?", n) }
  scope :max_beds,     ->(n) { where("bedrooms <= ?", n) }
  scope :min_sqft,     ->(n) { where("size_sqft >= ?", n) }
  scope :of_type,      ->(t) { where(property_type: Array(t)) }
  scope :of_tenure,    ->(t) { where(tenure: Array(t)) }

  # Returns a human-readable price string, e.g. "£450,000"
  def formatted_price
    return nil unless price_pence
    "£#{(price_pence / 100).to_s(:delimited)}"
  end

  # Text blob sent to ML service for embedding generation
  def embedding_text
    parts = [title, description]
    parts << "Key features: #{key_features.join(', ')}" if key_features.any?
    if property_enrichment
      e = property_enrichment
      parts << "#{e.distance_to_station_km&.round(1)}km to #{e.nearest_station_name}" if e.nearest_station_name
      parts << "Crime: #{e.crime_rate_category}" if e.crime_rate_category
      parts << "Flood risk: #{e.flood_risk}" if e.flood_risk
      parts << "Nearest school Ofsted: #{e.nearest_school_ofsted}" if e.nearest_school_ofsted
    end
    parts.compact.join("\n")
  end
end
