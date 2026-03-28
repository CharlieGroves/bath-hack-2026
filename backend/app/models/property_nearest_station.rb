class PropertyNearestStation < ApplicationRecord
  belongs_to :property
  validates :name, presence: true

  before_save :compute_walking_minutes

  private

  # Approximates walking time from straight-line distance.
  # 3 mph pace with a 1.3x detour factor to account for actual route length.
  WALKING_SPEED_MPH = 3.0
  DETOUR_MULTIPLIER = 1.3

  def compute_walking_minutes
    return unless distance_miles
    self.walking_minutes = (distance_miles * DETOUR_MULTIPLIER / WALKING_SPEED_MPH * 60).round
  end
end
