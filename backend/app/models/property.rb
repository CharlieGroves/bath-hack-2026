class Property < ApplicationRecord
  extend FriendlyId
  friendly_id :rightmove_id, use: :slugged

  belongs_to :area_price_growth, optional: true
  belongs_to :estate_agent, optional: true
  belongs_to :borough, optional: true
  has_one  :property_transport_snapshot, dependent: :destroy
  has_one  :property_crime_snapshot, dependent: :destroy
  has_many :property_images, dependent: :destroy
  belongs_to :air_quality_station, optional: true
  belongs_to :flood_risk_datapoint, optional: true
  has_many :property_nearest_stations, dependent: :destroy
  has_one :property_description_embedding, dependent: :destroy
  has_many :property_image_embeddings, dependent: :destroy
  has_one :property_monthly_bill_estimate, dependent: :destroy

  has_neighbors :image_embeddings_maxpool_vector, dimensions: 768

  after_commit :enqueue_transport_refresh,        on: %i[create update], if: :transport_refresh_needed?
  after_commit :enqueue_nearest_stations_refresh, on: %i[create update], if: :nearest_stations_refresh_needed?
  after_commit :enqueue_crime_refresh,            on: %i[create update], if: :crime_refresh_needed?
  after_commit :enqueue_estate_agent_resolution, on: %i[create update], if: :estate_agent_resolution_needed?
  after_commit :enqueue_description_embedding, on: %i[create update], if: :description_embedding_needed?
  after_commit :enqueue_image_embedding, on: %i[create update], if: :image_embedding_needed?
  after_commit :enqueue_monthly_bill_estimate_refresh, on: %i[create update], if: :monthly_bill_estimate_refresh_needed?

  STATUSES       = %w[active under_offer sold let].freeze
  PROPERTY_TYPES = %w[flat terraced semi_detached detached bungalow land other].freeze
  TENURES        = %w[freehold leasehold share_of_freehold].freeze
  EPC_RATINGS    = %w[A B C D E F G].freeze
  COUNCIL_BANDS  = %w[A B C D E F G H].freeze
  SHARED_OWNERSHIP_PERCENT_PATTERNS = [
    /\bshared\s+ownership\b/i,
    /\bpart[-\s]*buy[-\s]*part[-\s]*rent\b/i,
    /\b(?:share|ownership)\s*(?:purchase|available|to\s+buy|being\s+sold)?\s*:?\s*([1-9]\d?(?:\.\d+)?)\s*%\b/i,
    /\b([1-9]\d?(?:\.\d+)?)\s*%\s*(?:share|shared|ownership|of(?:\s+the)?\s+property)\b/i
  ].freeze
  MONTHLY_BILL_RELEVANT_FIELDS = %w[
    description
    price_pence
    property_type
    bedrooms
    bathrooms
    size_sqft
    tenure
    lease_years_remaining
    epc_rating
    council_tax_band
    service_charge_annual_pence
    utilities_text
    parking_text
    key_features
    postcode
    town
    raw_data
  ].freeze

  validates :rightmove_id, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  before_validation :derive_shared_ownership_flag

  scope :active,        -> { where(status: "active") }
  scope :for_sale,      -> { where.not(status: %w[let]) }
  scope :by_newest,     -> { order(listed_at: :desc) }
  scope :by_price_asc,  -> { order(price_pence: :asc) }
  scope :by_price_desc, -> { order(price_pence: :desc) }

  # Classical filter scopes — used by PropertySearch service
  scope :min_price,    ->(p) { where("price_pence >= ?", p) }
  scope :max_price,    ->(p) { where("price_pence <= ?", p) }
  scope :min_beds,     ->(n) { where("bedrooms >= ?", n) }
  scope :max_beds,     ->(n) { where("bedrooms <= ?", n) }
  scope :min_sqft,     ->(n) { where("size_sqft >= ?", n) }
  scope :of_type,      ->(t) { where(property_type: Array(t)) }
  scope :of_tenure,    ->(t) { where(tenure: Array(t)) }
  scope :with_coordinates, -> { where.not(latitude: nil, longitude: nil) }
  scope :within_bounding_box, lambda { |bounding_box|
    where(latitude: bounding_box.fetch(:south)..bounding_box.fetch(:north))
      .where(longitude: bounding_box.fetch(:west)..bounding_box.fetch(:east))
  }
  scope :within_station_miles,   ->(m) { joins(:property_nearest_stations).where("property_nearest_stations.distance_miles <= ?", m).distinct }
  scope :within_station_minutes, ->(t) { joins(:property_nearest_stations).where("property_nearest_stations.walking_minutes <= ?", t).distinct }
  scope :max_daqi,               ->(n) { joins(:air_quality_station).where("air_quality_stations.daqi_index <= ?", n) }
  scope :max_flood_risk_band,    ->(n) { joins(:flood_risk_datapoint).where("flood_risk_datapoints.risk_band <= ?", n) }
  scope :max_road_noise_lden,    ->(n) { joins(:property_transport_snapshot).where("property_transport_snapshots.status = 'ready'").where("CAST(property_transport_snapshots.road_data -> 'metrics' ->> 'lden' AS NUMERIC) <= ?", n) }
  scope :max_rail_noise_lden,    ->(n) { joins(:property_transport_snapshot).where("property_transport_snapshots.status = 'ready'").where("CAST(property_transport_snapshots.rail_data -> 'metrics' ->> 'lden' AS NUMERIC) <= ?", n) }
  scope :max_flight_noise_lden,  ->(n) { joins(:property_transport_snapshot).where("property_transport_snapshots.status = 'ready'").where("CAST(property_transport_snapshots.flight_data -> 'metrics' ->> 'lden' AS NUMERIC) <= ?", n) }
  scope :with_shared_ownership,  ->(flag) { where(is_shared_ownership: ActiveModel::Type::Boolean.new.cast(flag)) }
  scope :max_crime_rate,         ->(n) { joins(:property_crime_snapshot).where("property_crime_snapshots.status = 'ready'").where("property_crime_snapshots.avg_monthly_crimes <= ?", n) }
  scope :min_bathrooms,          ->(n) { where("bathrooms >= ?", n) }
  scope :max_price_per_sqft,     ->(p) { where("price_per_sqft_pence <= ?", p) }
  scope :min_price_per_sqft,     ->(p) { where("price_per_sqft_pence >= ?", p) }
  scope :epc_rating_min,         ->(r) { where("epc_rating >= ?", r.upcase) }
  scope :max_nte_score,          ->(n) { joins(:borough).where("boroughs.nte_score <= ?", n) }
  scope :min_nte_score,          ->(n) { joins(:borough).where("boroughs.nte_score >= ?", n) }
  scope :min_life_satisfaction,  ->(n) { joins(:borough).where("boroughs.life_satisfaction_score >= ?", n) }
  scope :min_happiness,          ->(n) { joins(:borough).where("boroughs.happiness_score >= ?", n) }
  scope :max_anxiety,            ->(n) { joins(:borough).where("boroughs.anxiety_score <= ?", n) }

  def self.shared_ownership_from_description?(text)
    description_text = text.to_s
    return false if description_text.blank?

    SHARED_OWNERSHIP_PERCENT_PATTERNS.any? { |pattern| description_text.match?(pattern) }
  end

  # Recomputes element-wise max of all +embedding_vector+ rows for this listing (see +PropertyImageEmbedding+).
  def self.refresh_image_embeddings_maxpool!(property_id)
    property = find_by(id: property_id)
    return unless property

    pooled = PropertyImageEmbedding.maxpool_vector_array_for_property(property_id)
    property.update_columns(
      image_embeddings_maxpool_vector: pooled,
      updated_at: Time.current
    )
  end

  # @param query_vector [Array<Numeric>] 768 floats (max-pool space; same dim as image embeddings)
  def self.nearest_by_maxpool_vector(query_vector, limit: 20, distance: "cosine")
    dim = PropertyImageEmbedding::EXPECTED_DIMENSIONS
    unless query_vector.is_a?(Array) && query_vector.size == dim
      raise ArgumentError, "expected Array of #{dim} floats"
    end

    nearest_neighbors(:image_embeddings_maxpool_vector, query_vector.map(&:to_f), distance: distance).limit(limit)
  end

  # Returns a human-readable price string, e.g. "£450,000"
  def formatted_price
    return nil unless price_pence

    "£#{ActiveSupport::NumberHelper.number_to_delimited(price_pence / 100)}"
  end

  private

  def transport_refresh_needed?
    return false if latitude.blank? || longitude.blank?

    saved_change_to_latitude? ||
      saved_change_to_longitude? ||
      property_transport_snapshot.nil? ||
      property_transport_snapshot.fetched_at.nil? ||
      property_transport_snapshot.fetched_at < 24.hours.ago
  end

  def enqueue_transport_refresh
    PropertyTransportSnapshotJob.perform_later(id)
  end

  def nearest_stations_refresh_needed?
    saved_change_to_raw_data? || property_nearest_stations.empty?
  end

  def enqueue_nearest_stations_refresh
    PropertyNearestStationsJob.perform_later(id)
  end

  def crime_refresh_needed?
    return false if latitude.blank? || longitude.blank?

    saved_change_to_latitude? ||
      saved_change_to_longitude? ||
      property_crime_snapshot.nil? ||
      property_crime_snapshot.fetched_at.nil? ||
      property_crime_snapshot.fetched_at < 7.days.ago
  end

  def enqueue_crime_refresh
    PropertyCrimeSnapshotJob.perform_later(id)
  end

  def estate_agent_resolution_needed?
    return false if agent_name.blank?

    estate_agent_id.nil? || previous_changes.key?("agent_name")
  end

  def enqueue_estate_agent_resolution
    EstateAgentLinkJob.perform_later(id)
  end

  def description_embedding_needed?
    return false if description.blank?

    property_description_embedding.nil? || previous_changes.key?("description")
  end

  def enqueue_description_embedding
    PropertyDescriptionEmbedJob.perform_later(id)
  end

  def image_embedding_needed?
    urls = Array(photo_urls).map(&:to_s).map(&:strip).reject(&:blank?)
    return false if urls.empty?

    property_image_embeddings.empty? || previous_changes.key?("photo_urls")
  end

  def enqueue_image_embedding
    PropertyImageEmbedJob.perform_later(id)
  end

  def monthly_bill_estimate_refresh_needed?
    has_inputs = [
      description,
      price_pence,
      size_sqft,
      council_tax_band,
      service_charge_annual_pence
    ].any?(&:present?)
    return false unless has_inputs
    return true if property_monthly_bill_estimate.nil?

    (previous_changes.keys & MONTHLY_BILL_RELEVANT_FIELDS).any? ||
      property_monthly_bill_estimate.status != "ready" ||
      property_monthly_bill_estimate.fetched_at.nil? ||
      property_monthly_bill_estimate.fetched_at < 30.days.ago
  end

  def enqueue_monthly_bill_estimate_refresh
    PropertyMonthlyBillEstimateJob.perform_later(id)
  end

  def derive_shared_ownership_flag
    self.is_shared_ownership = self.class.shared_ownership_from_description?(description)
  end
end
