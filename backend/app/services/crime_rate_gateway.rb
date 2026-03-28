require "date"

# Application-facing entry point for UK Police street crime data.
# Hides HTTP details and returns an average count over a rolling window of months.
#
# Usage:
#   CrimeRateGateway.average_crime_rate(
#     lat: 52.629729,
#     lng: -1.131592,
#     crime_type: "burglary",
#     months: 3
#   )
#   # => 45.67  (mean crimes per month over the 3 full months before this month)
#
# +crime_type+ should match a Police API category slug (see /api/crime-categories),
# e.g. "burglary", "vehicle-crime", "all-crime". Human-readable labels are
# normalized (downcased, spaces → hyphens).
class CrimeRateGateway
  # @param lat [Numeric]
  # @param lng [Numeric]
  # @param crime_type [String] category slug or label (e.g. "Burglary" → "burglary")
  # @param months [Integer] how many full calendar months to include (must be >= 1).
  #   Uses the +months+ complete months immediately before the current calendar month
  #   (the current month is excluded).
  # @return [Float] mean number of crimes per month in that window
  def self.average_crime_rate(lat:, lng:, crime_type:, months:)
    n = Integer(months)
    raise ArgumentError, "months must be at least 1" if n < 1

    category = normalize_crime_type(crime_type)
    raise ArgumentError, "crime_type must be non-empty" if category.empty?

    ym_list = prior_full_months_before_current(n)
    counts = ym_list.map do |date_str|
      CrimeRate.fetch_street_crimes(
        category: category,
        lat: lat,
        lng: lng,
        date: date_str
      ).size
    end

    counts.sum.to_f / counts.size
  end

  def self.normalize_crime_type(crime_type)
    s = crime_type.to_s.strip.downcase.tr(" ", "-").tr("_", "-")
    s.gsub(/[^a-z0-9\-]/, "")
  end

  # YYYY-MM strings for the +count+ calendar months immediately before today's month.
  def self.prior_full_months_before_current(count)
    today = Date.today
    first_this_month = Date.new(today.year, today.month, 1)
    (1..count).map do |i|
      d = first_this_month << i
      format("%04d-%02d", d.year, d.month)
    end
  end
  private_class_method :prior_full_months_before_current
end
