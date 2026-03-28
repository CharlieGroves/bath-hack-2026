class AirQualityStation < ApplicationRecord
  has_many :properties, dependent: :nullify

  DAQI_BANDS = {
    (1..3)  => "Low",
    (4..6)  => "Moderate",
    (7..8)  => "High",
    (9..10) => "Very High"
  }.freeze

  validates :external_id, presence: true, uniqueness: true
  validates :name,        presence: true
  validates :latitude,    presence: true
  validates :longitude,   presence: true

  scope :with_daqi, -> { where.not(daqi_index: nil) }

  def daqi_band_label
    return nil unless daqi_index
    DAQI_BANDS.find { |range, _| range.include?(daqi_index) }&.last
  end
end
