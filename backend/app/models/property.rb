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

  after_commit :enqueue_transport_refresh,        on: %i[create update], if: :transport_refresh_needed?
  after_commit :enqueue_nearest_stations_refresh, on: %i[create update], if: :nearest_stations_refresh_needed?
  after_commit :enqueue_crime_refresh,            on: %i[create update], if: :crime_refresh_needed?
  after_commit :enqueue_estate_agent_resolution, on: %i[create update], if: :estate_agent_resolution_needed?
  after_commit :enqueue_description_embedding, on: %i[create update], if: :description_embedding_needed?
  after_commit :enqueue_image_embedding, on: %i[create update], if: :image_embedding_needed?

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
end
