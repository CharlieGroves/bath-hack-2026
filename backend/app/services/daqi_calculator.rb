# Converts annual-mean pollutant concentrations (µg/m³) to UK DAQI indices (1–10).
#
# Standard DAQI uses peak hourly/8-hour thresholds. Because we work with
# annual means (which are far lower than peak values), we use purpose-built
# annual-mean breakpoints derived from UK Air Quality Objectives and WHO
# guidelines, scaled to produce a meaningful spread across London stations.
#
# Composite DAQI: the maximum single-pollutant index across all measured pollutants.
#
# Usage:
#   DaqiCalculator.index(:NO2, 35.4)  # => 5
#   DaqiCalculator.composite({ "NO2" => 35.4, "PM2.5" => 12.1 })  # => 5
#   DaqiCalculator.band_label(5)       # => "Moderate"
class DaqiCalculator
  BAND_LABELS = {
    (1..3)  => "Low",
    (4..6)  => "Moderate",
    (7..8)  => "High",
    (9..10) => "Very High"
  }.freeze

  # Annual-mean thresholds (µg/m³) for each DAQI index 1–10.
  # Each inner array is [max_value_for_this_band].  Index into THRESHOLDS[pollutant]
  # is (daqi_index - 1).  Index 10 catches everything above the last threshold.
  #
  # Sources:
  #   NO2  — UK annual mean objective 40 µg/m³; WHO 10 µg/m³
  #   PM2.5— UK target 10 µg/m³; WHO 5 µg/m³
  #   PM10 — UK 24-hour objective 50 µg/m³; WHO annual 15 µg/m³
  #   O3   — no UK annual mean objective; WHO 60 µg/m³ peak season
  #   SO2  — UK 24-hour objective 125 µg/m³; annual means typically <20 µg/m³
  THRESHOLDS = {
    "NO2"  => [10, 15, 20, 25, 32, 40, 50, 62, 80, Float::INFINITY],
    "PM2.5"=> [ 4,  6,  9, 12, 15, 20, 25, 30, 40, Float::INFINITY],
    "PM10" => [ 8, 11, 15, 19, 23, 28, 33, 40, 50, Float::INFINITY],
    "O3"   => [30, 40, 50, 55, 60, 70, 80, 90,100, Float::INFINITY],
    "SO2"  => [ 3,  5,  8, 12, 18, 25, 35, 50, 75, Float::INFINITY]
  }.freeze

  # Returns a DAQI index (1–10) for a given pollutant and annual-mean concentration.
  # Returns nil if the pollutant is unknown.
  #
  # @param pollutant [String]  "NO2", "O3", "PM2.5", "PM10", "SO2"
  # @param mean_ug_m3 [Numeric]
  def self.index(pollutant, mean_ug_m3)
    steps = THRESHOLDS[pollutant.to_s]
    return nil unless steps

    steps.each_with_index do |upper, i|
      return i + 1 if mean_ug_m3 <= upper
    end
    10
  end

  # Returns the highest single-pollutant DAQI index from a hash of
  # { pollutant => annual_mean_ug_m3 } (any nils / unknowns are skipped).
  def self.composite(means_by_pollutant)
    indices = means_by_pollutant.filter_map do |pollutant, mean|
      next if mean.nil?
      index(pollutant, mean)
    end
    indices.max
  end

  # Maps a DAQI index (1–10) to its band label.
  def self.band_label(daqi_index)
    return nil unless daqi_index
    BAND_LABELS.find { |range, _| range.include?(daqi_index) }&.last
  end
end
