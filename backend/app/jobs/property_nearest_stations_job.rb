class PropertyNearestStationsJob < ApplicationJob
  queue_as :scraping

  def perform(property_id)
    property = Property.find_by(id: property_id)
    return unless property

    scraper  = RightmoveScraper.new
    stations = extract_stations(property, scraper)
    return if stations.empty?

    property.property_nearest_stations.destroy_all
    property.property_nearest_stations.create!(stations)
  end

  private

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
