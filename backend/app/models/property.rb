class Property < ApplicationRecord
  extend FriendlyId
  friendly_id :rightmove_id, use: :slugged

  has_one  :property_transport_snapshot, dependent: :destroy
  has_many :property_images, dependent: :destroy

  after_commit :enqueue_transport_refresh, on: %i[create update], if: :transport_refresh_needed?

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
end
