require "json"
require "pathname"
require "set"

namespace :ml do
  desc "Export the current property dataset for local ML training"
  task export_dataset: :environment do
    output_path = Pathname.new(ENV.fetch("OUTPUT", Rails.root.join("..", "ml-training", "data", "properties.json").to_s))
    output_path.dirname.mkpath

    include_map = {
      property_transport_snapshot: "property_transport_snapshots",
      property_crime_snapshot: "property_crime_snapshots",
      property_nearest_stations: "property_nearest_stations",
      air_quality_station: "air_quality_stations",
      area_price_growth: "area_price_growths",
      borough: "boroughs",
      estate_agent: "estate_agents"
    }
    available_includes = include_map.filter_map do |association, table_name|
      association if ActiveRecord::Base.connection.data_source_exists?(table_name)
    rescue StandardError
      nil
    end

    properties = Property.includes(*available_includes).order(:id)

    payload = {
      generated_at: Time.current.iso8601,
      source: "rails_property_export",
      property_count: properties.count,
      properties: properties.map { |property| PropertyMachineLearningPayloadBuilder.new(property).as_json }
    }

    output_path.write(JSON.pretty_generate(payload))
    puts "Exported #{payload[:property_count]} properties to #{output_path}"
  end

  desc <<~DESC
    Collect a larger current-listings dataset directly from Rightmove for valuation training.

    Optional:
      OUTPUT          - Output JSON path (default: ../ml-training/data/properties_live.json)
      URL             - Rightmove search URL (default: London for-sale search)
      MIN_PRICE       - Minimum listing price in pounds (default: 200000)
      MAX_PRICE       - Maximum listing price in pounds (default: 10000000)
      BAND_SIZE       - Price band width in pounds (default: 250000)
      PER_BAND_LIMIT  - Max property ids to collect per price band (default: 30)
      MAX_LISTINGS    - Max listings to fetch in detail (default: 1200)
      DELAY           - Delay between detail fetches in seconds (default: 0.15)
  DESC
  task collect_live_dataset: :environment do
    output_path = Pathname.new(
      ENV.fetch("OUTPUT", Rails.root.join("..", "ml-training", "data", "properties_live.json").to_s)
    )
    output_path.dirname.mkpath

    url = ENV.fetch(
      "URL",
      "https://www.rightmove.co.uk/property-for-sale/find.html?channel=BUY&index=0&newHome=false&retirement=false&auction=false&partBuyPartRent=false&sortType=2&areaSizeUnit=sqft&locationIdentifier=REGION%5E87490&transactionType=BUY&displayLocationIdentifier=London-87490.html"
    )
    min_price = ENV.fetch("MIN_PRICE", "200000").to_i
    max_price = ENV.fetch("MAX_PRICE", "10000000").to_i
    band_size = ENV.fetch("BAND_SIZE", "250000").to_i
    per_band_limit = ENV.fetch("PER_BAND_LIMIT", "30").to_i
    max_listings = ENV.fetch("MAX_LISTINGS", "1200").to_i
    delay = ENV.fetch("DELAY", "0.15").to_f

    search_scraper = RightmoveSearchScraper.new
    detail_scraper = RightmoveScraper.new
    listing_ids = []
    bands = (min_price...max_price).step(band_size).map { |low| [low, low + band_size] }

    puts "Collecting listing ids across #{bands.length} price bands..."
    bands.each_with_index do |(low, high), index|
      band_url = set_price_params(url, low, high)
      print "[Band #{index + 1}/#{bands.length}] £#{number_with_delimiter(low)}-£#{number_with_delimiter(high)}: "

      begin
        ids = search_scraper.property_ids(band_url, limit: per_band_limit)
        puts "#{ids.length} ids"
        listing_ids.concat(ids)
      rescue RightmoveSearchScraper::ScrapingError => e
        puts "error (#{e.message})"
      end
    end

    listing_ids = listing_ids.uniq.first(max_listings)
    puts "Fetching #{listing_ids.length} unique listing payloads..."

    collected = []
    listing_ids.each_with_index do |rightmove_id, index|
      begin
        attrs = detail_scraper.fetch_listing(rightmove_id)
        payload = build_scraped_listing_payload(attrs, detail_scraper)
        unless payload[:price_pence].present?
          puts "[#{index + 1}/#{listing_ids.length}] skipped #{rightmove_id}: missing price"
          next
        end

        collected << payload
        puts "[#{index + 1}/#{listing_ids.length}] collected #{rightmove_id} (#{collected.length} saved)"
      rescue RightmoveScraper::ScrapingError => e
        puts "[#{index + 1}/#{listing_ids.length}] skipped #{rightmove_id}: #{e.message}"
      ensure
        sleep(delay) if delay.positive?
      end
    end

    payload = {
      generated_at: Time.current.iso8601,
      source: "rightmove_live_collection",
      property_count: collected.length,
      search_url: url,
      min_price_gbp: min_price,
      max_price_gbp: max_price,
      band_size_gbp: band_size,
      per_band_limit: per_band_limit,
      properties: collected
    }

    output_path.write(JSON.pretty_generate(payload))
    puts "Exported #{payload[:property_count]} live listings to #{output_path}"
  end

  def build_scraped_listing_payload(attrs, detail_scraper)
    raw_data = attrs[:raw_data] || {}
    property_data = raw_data["propertyData"] || {}
    photo_urls = Array(attrs[:photo_urls]).compact
    key_features = Array(attrs[:key_features]).compact

    {
      rightmove_id: attrs[:rightmove_id],
      title: attrs[:title],
      description: attrs[:description],
      address_line_1: attrs[:address_line_1],
      town: attrs[:town],
      postcode: attrs[:postcode],
      price_pence: attrs[:price_pence],
      price_per_sqft_pence: attrs[:price_per_sqft_pence],
      bedrooms: attrs[:bedrooms],
      bathrooms: attrs[:bathrooms],
      size_sqft: attrs[:size_sqft],
      property_type: attrs[:property_type],
      tenure: attrs[:tenure],
      lease_years_remaining: attrs[:lease_years_remaining],
      service_charge_annual_pence: attrs[:service_charge_annual_pence],
      epc_rating: attrs[:epc_rating],
      council_tax_band: attrs[:council_tax_band],
      utilities_text: attrs[:utilities_text],
      parking_text: attrs[:parking_text],
      latitude: attrs[:latitude]&.to_f,
      longitude: attrs[:longitude]&.to_f,
      has_floor_plan: attrs[:has_floor_plan],
      has_virtual_tour: attrs[:has_virtual_tour],
      status: attrs[:status],
      listed_at: attrs[:listed_at]&.respond_to?(:iso8601) ? attrs[:listed_at].iso8601 : nil,
      photo_urls: photo_urls,
      key_features: key_features,
      photo_count: photo_urls.size,
      key_feature_count: key_features.size,
      raw_address: {
        display_address: property_data.dig("address", "displayAddress"),
        outcode: property_data.dig("address", "outcode"),
        town: property_data.dig("address", "town")
      },
      raw_property_data: {
        tags: property_data["tags"] || [],
        sizings: property_data["sizings"] || [],
        features: property_data["features"] || {},
        rooms: property_data["rooms"] || []
      },
      area_price_growth: nil,
      borough: nil,
      estate_agent: attrs[:agent_name].present? ? { display_name: attrs[:agent_name], rating: nil } : nil,
      noise: nil,
      crime: nil,
      air_quality: nil,
      nearest_stations: detail_scraper.extract_nearest_stations(raw_data).map do |station|
        {
          name: station[:name],
          distance_miles: station[:distance_miles],
          walking_minutes: nil,
          transport_type: station[:transport_type]
        }
      end
    }
  end

  def number_with_delimiter(value)
    ActiveSupport::NumberHelper.number_to_delimited(value)
  end

  def set_price_params(url, min, max)
    uri = URI.parse(url)
    params = URI.decode_www_form(uri.query || "").to_h
    params["minPrice"] = min.to_s
    params["maxPrice"] = max.to_s
    uri.query = URI.encode_www_form(params)
    uri.to_s
  end
end
