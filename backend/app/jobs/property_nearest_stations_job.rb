class PropertyNearestStationsJob < ApplicationJob
  queue_as :scraping

  def perform(property_id)
    property = Property.find_by(id: property_id)
    return unless property

    scraper  = RightmoveScraper.new
    stations = extract_stations(property, scraper)
    return if stations.empty?

    property.property_nearest_stations.destroy_all
    property.property_nearest_stations.create!(stations.map { |s| s.merge(termini: termini_for(s)) })
  end

  private
  def termini_for(station)
    return [] unless station[:transport_type] == "national_rail"

    normalised = station[:name].to_s.sub(/ Station$/i, "").strip
    ::STATION_TERMINI.fetch(normalised, [])
  end

  def extract_stations(property, scraper)
    if property.raw_data.present?
      result = scraper.extract_nearest_stations(property.raw_data)
      return result if result.any?
    end

    attrs = scraper.fetch_listing(property.rightmove_id)
    scraper.extract_nearest_stations(attrs[:raw_data])
  rescue RightmoveScraper::ScrapingError
    []
  end
end
