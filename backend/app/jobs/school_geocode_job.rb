# Geocodes a single school's postcode via postcodes.io.
# Used to (re)geocode individual schools that were missed during bulk import.
#
#   SchoolGeocodeJob.perform_later(school_id)
class SchoolGeocodeJob < ApplicationJob
  queue_as :default

  POSTCODES_IO = "https://api.postcodes.io/postcodes/".freeze

  def perform(school_id)
    school = School.find_by(id: school_id)
    return unless school

    coords = geocode_via_postcodes_io(school.postcode) ||
             geocode_via_nominatim(school)

    unless coords
      Rails.logger.warn("[SchoolGeocodeJob] Could not geocode school #{school_id} (#{school.postcode})")
      return
    end

    school.update_columns(latitude: coords[:latitude], longitude: coords[:longitude])
    Rails.logger.info("[SchoolGeocodeJob] School #{school_id} → #{coords[:latitude]}, #{coords[:longitude]}")
  rescue Faraday::Error, JSON::ParserError => e
    Rails.logger.error("[SchoolGeocodeJob] School #{school_id}: #{e.message}")
    raise
  end

  private

  def geocode_via_postcodes_io(postcode)
    response = Faraday.get(
      "#{POSTCODES_IO}#{CGI.escape(postcode.gsub(/\s+/, ''))}",
      {}, "Accept" => "application/json"
    )
    return nil unless response.success?

    result = JSON.parse(response.body)["result"]
    return nil unless result

    { latitude: result["latitude"], longitude: result["longitude"] }
  rescue Faraday::Error, JSON::ParserError
    nil
  end

  def geocode_via_nominatim(school)
    query = [school.address1, school.town, school.postcode, "UK"].compact.reject(&:empty?).join(", ")
    response = Faraday.get(
      "https://nominatim.openstreetmap.org/search",
      { q: query, format: "json", limit: 1 },
      "Accept"     => "application/json",
      "User-Agent" => "BathHack/1.0 (+https://github.com/CharlieGroves/bath-hack-2026)"
    )
    return nil unless response.success?

    results = JSON.parse(response.body)
    return nil if results.empty?

    { latitude: results[0]["lat"].to_f, longitude: results[0]["lon"].to_f }
  rescue Faraday::Error, JSON::ParserError
    nil
  end
end
