require "json"
require "pathname"
require "set"
require "csv"

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

  desc <<~DESC
    Import a collected ML dataset into the local properties tables without relying on Sidekiq.

    Optional:
      INPUT  - JSON dataset path (default: ../ml-training/data/properties_valuation_training.json)
  DESC
  task import_training_dataset: :environment do
    input_path = Pathname.new(
      ENV.fetch("INPUT", Rails.root.join("..", "ml-training", "data", "properties_valuation_training.json").to_s)
    )
    payload = JSON.parse(input_path.read)
    records = payload.fetch("properties", [])
    now = Time.current

    property_rows = records.filter_map do |record|
      rightmove_id = record["rightmove_id"].presence || record[:rightmove_id].presence
      next unless rightmove_id.present?

      {
        rightmove_id: rightmove_id.to_s,
        slug: rightmove_id.to_s,
        title: record["title"] || record[:title],
        description: record["description"] || record[:description],
        key_features: Array(record["key_features"] || record[:key_features]),
        photo_urls: Array(record["photo_urls"] || record[:photo_urls]),
        price_pence: record["price_pence"] || record[:price_pence],
        price_per_sqft_pence: record["price_per_sqft_pence"] || record[:price_per_sqft_pence],
        property_type: record["property_type"] || record[:property_type],
        bedrooms: record["bedrooms"] || record[:bedrooms],
        bathrooms: record["bathrooms"] || record[:bathrooms],
        size_sqft: record["size_sqft"] || record[:size_sqft],
        tenure: record["tenure"] || record[:tenure],
        lease_years_remaining: record["lease_years_remaining"] || record[:lease_years_remaining],
        epc_rating: record["epc_rating"] || record[:epc_rating],
        council_tax_band: record["council_tax_band"] || record[:council_tax_band],
        service_charge_annual_pence: record["service_charge_annual_pence"] || record[:service_charge_annual_pence],
        address_line_1: record["address_line_1"] || record[:address_line_1],
        town: record["town"] || record[:town],
        postcode: record["postcode"] || record[:postcode],
        latitude: record["latitude"] || record[:latitude],
        longitude: record["longitude"] || record[:longitude],
        has_floor_plan: !!(record["has_floor_plan"] || record[:has_floor_plan]),
        has_virtual_tour: !!(record["has_virtual_tour"] || record[:has_virtual_tour]),
        utilities_text: record["utilities_text"] || record[:utilities_text],
        parking_text: record["parking_text"] || record[:parking_text],
        status: record["status"].presence || record[:status].presence || "active",
        listed_at: parse_time(record["listed_at"] || record[:listed_at]),
        raw_data: synthesized_raw_data(record),
        created_at: now,
        updated_at: now
      }
    end

    Property.upsert_all(property_rows, unique_by: :index_properties_on_rightmove_id) if property_rows.any?

    id_map = Property.where(rightmove_id: property_rows.map { |row| row[:rightmove_id] }).pluck(:rightmove_id, :id).to_h
    target_property_ids = id_map.values

    PropertyNearestStation.where(property_id: target_property_ids).delete_all if target_property_ids.any?

    station_rows = records.flat_map do |record|
      property_id = id_map[(record["rightmove_id"] || record[:rightmove_id]).to_s]
      next [] unless property_id

      Array(record["nearest_stations"] || record[:nearest_stations]).filter_map do |station|
        distance = station["distance_miles"] || station[:distance_miles]
        next unless station["name"].present? || station[:name].present?

        {
          property_id: property_id,
          name: station["name"] || station[:name],
          distance_miles: distance,
          transport_type: station["transport_type"] || station[:transport_type],
          walking_minutes: station["walking_minutes"] || station[:walking_minutes] || estimated_walking_minutes(distance),
          created_at: now,
          updated_at: now
        }
      end
    end
    PropertyNearestStation.insert_all(station_rows) if station_rows.any?

    puts "Imported #{property_rows.size} properties from #{input_path}"
    puts "Imported #{station_rows.size} nearest-station rows"
  end

  desc <<~DESC
    Print enrichment coverage status for the current ML dataset scope.

    Optional:
      INPUT         - JSON dataset path (default: ../ml-training/data/properties_valuation_training.json)
      START_OFFSET  - Skip first N scoped properties (default: 0)
      MAX_PROPERTIES- Limit to first N scoped properties after offset (default: all)
  DESC
  task enrichment_status: :environment do
    input_path = Pathname.new(
      ENV.fetch("INPUT", Rails.root.join("..", "ml-training", "data", "properties_valuation_training.json").to_s)
    )
    scope = scoped_training_properties(input_path)
    property_count = scope.count
    property_ids = scope.pluck(:id)
    zero_counts = {
      property_count: 0,
      crime_ready: 0,
      transport_ready: 0,
      transport_noise_ready: 0,
      air_quality_assigned: 0,
      nearest_station_count: 0
    }

    if property_ids.empty?
      puts JSON.pretty_generate(zero_counts)
      next
    end

    crime_ready = scope
      .joins(:property_crime_snapshot)
      .where(property_crime_snapshots: { status: "ready" })
      .count

    transport_ready = scope
      .joins(:property_transport_snapshot)
      .where(property_transport_snapshots: { status: "ready" })
      .count

    transport_noise_ready = scope
      .joins(:property_transport_snapshot)
      .where(property_transport_snapshots: { status: "ready" })
      .where(
        "(property_transport_snapshots.road_data -> 'metrics' ->> 'lden') IS NOT NULL OR " \
        "(property_transport_snapshots.rail_data -> 'metrics' ->> 'lden') IS NOT NULL OR " \
        "(property_transport_snapshots.flight_data -> 'metrics' ->> 'lden') IS NOT NULL"
      )
      .count

    air_quality_assigned = scope
      .joins(:air_quality_station)
      .where.not(air_quality_stations: { daqi_index: nil })
      .count

    nearest_station_count = PropertyNearestStation
      .where(property_id: property_ids)
      .distinct
      .count(:property_id)

    pct = ->(count) do
      return 0.0 if property_count.zero?

      ((count.to_f / property_count) * 100.0).round(1)
    end

    status = {
      property_count: property_count,
      crime_ready: crime_ready,
      crime_ready_pct: pct.call(crime_ready),
      transport_ready: transport_ready,
      transport_ready_pct: pct.call(transport_ready),
      transport_noise_ready: transport_noise_ready,
      transport_noise_ready_pct: pct.call(transport_noise_ready),
      air_quality_assigned: air_quality_assigned,
      air_quality_assigned_pct: pct.call(air_quality_assigned),
      nearest_station_count: nearest_station_count,
      nearest_station_pct: pct.call(nearest_station_count)
    }

    puts JSON.pretty_generate(status)
  end

  desc <<~DESC
    Backfill public quantitative enrichments synchronously for the imported ML training dataset.

    Optional:
      INPUT                  - JSON dataset path (default: ../ml-training/data/properties_valuation_training.json)
      RUN_CRIME              - 1/0 (default: 1)
      RUN_TRANSPORT          - 1/0 (default: 1)
      RUN_AIR_QUALITY        - 1/0 (default: 1)
      RUN_AREA_PRICE_GROWTH  - 1/0 (default: 1)
      ONLY_MISSING           - 1/0 (default: 0)
      BATCH_SIZE             - Batch size for scans and assignments (default: 200)
      START_OFFSET           - Skip first N scoped properties (default: 0)
      MAX_PROPERTIES         - Limit to first N scoped properties after offset (default: all)
      SLEEP_SECONDS          - Sleep after network fetches (default: 0.0)
  DESC
  task enrich_training_dataset: :environment do
    input_path = Pathname.new(
      ENV.fetch("INPUT", Rails.root.join("..", "ml-training", "data", "properties_valuation_training.json").to_s)
    )
    scope = scoped_training_properties(input_path)
    only_missing = env_enabled?("ONLY_MISSING", default: false)
    batch_size = [ENV.fetch("BATCH_SIZE", "200").to_i, 1].max
    sleep_seconds = [ENV.fetch("SLEEP_SECONDS", "0.0").to_f, 0.0].max

    puts "Scoped properties: #{scope.count} (ONLY_MISSING=#{only_missing ? 1 : 0}, BATCH_SIZE=#{batch_size}, SLEEP_SECONDS=#{sleep_seconds})"

    if ENV.fetch("RUN_AREA_PRICE_GROWTH", "1") == "1"
      csv_path = Rails.root.join("data", "london_area_house_growth_per_year.csv")
      if csv_path.exist?
        AreaPriceGrowthImporter.new(csv_path: csv_path).call
        area_scope = stage_scope(scope, :area_price_growth, only_missing: only_missing)
        puts "Area price growth linked for #{area_scope.where.not(area_price_growth_id: nil).count} scoped properties"
      end
    end

    if ENV.fetch("RUN_CRIME", "1") == "1"
      tolerance = 0.005
      crime_scope = stage_scope(scope, :crime, only_missing: only_missing).where.not(latitude: nil, longitude: nil)
      crime_buckets = grouped_coordinate_buckets(crime_scope)
      total_properties = crime_buckets.values.sum(&:length)
      processed = 0
      errors = 0
      started_at = Time.current

      puts "Crime buckets: #{crime_buckets.size} (#{total_properties} properties)"

      crime_buckets.each_value do |properties_in_bucket|
        anchor = properties_in_bucket.first
        existing = PropertyCrimeSnapshot
          .where(status: "ready")
          .where(latitude: (anchor[:lat] - tolerance)..(anchor[:lat] + tolerance))
          .where(longitude: (anchor[:lng] - tolerance)..(anchor[:lng] + tolerance))
          .order(fetched_at: :desc)
          .first

        avg = existing&.avg_monthly_crimes
        fetched = existing&.fetched_at

        if avg.nil?
          avg = CrimeRateGateway.average_crime_rate(
            lat: anchor[:lat],
            lng: anchor[:lng],
            crime_type: "all-crime",
            months: 3
          )
          fetched = Time.current
          sleep(sleep_seconds) if sleep_seconds.positive?
        end

        properties_in_bucket.each do |prop|
          property = Property.find(prop[:id])
          snapshot = property.property_crime_snapshot || property.build_property_crime_snapshot
          snapshot.update!(
            latitude: prop[:lat],
            longitude: prop[:lng],
            avg_monthly_crimes: avg,
            fetched_at: fetched,
            status: "ready",
            error_message: nil
          )
        end
      rescue CrimeRate::RequestError => e
        errors += properties_in_bucket.length
        properties_in_bucket.each do |prop|
          property = Property.find(prop[:id])
          snapshot = property.property_crime_snapshot || property.build_property_crime_snapshot
          snapshot.update!(
            latitude: prop[:lat],
            longitude: prop[:lng],
            status: "failed",
            error_message: e.message
          )
        end
        puts "Crime warn for bucket #{anchor[:lat]},#{anchor[:lng]}: #{e.message}"
      ensure
        processed += properties_in_bucket.length
        log_throughput("Crime", processed: processed, total: total_properties, errors: errors, started_at: started_at)
      end

      puts "Crime snapshots ready: #{scope.joins(:property_crime_snapshot).where(property_crime_snapshots: { status: 'ready' }).count}"
    end

    if ENV.fetch("RUN_TRANSPORT", "1") == "1"
      transport_scope = stage_scope(scope, :transport, only_missing: only_missing).where.not(latitude: nil, longitude: nil)
      transport_buckets = grouped_coordinate_buckets(transport_scope)
      total_properties = transport_buckets.values.sum(&:length)
      processed = 0
      errors = 0
      started_at = Time.current

      puts "Transport buckets: #{transport_buckets.size} (#{total_properties} properties)"

      transport_buckets.each_value do |properties_in_bucket|
        anchor = properties_in_bucket.first
        payload = TransportGateway.new.fetch(latitude: anchor[:lat], longitude: anchor[:lng])
        fetched_at = Time.current
        sleep(sleep_seconds) if sleep_seconds.positive?

        properties_in_bucket.each do |prop|
          property = Property.find(prop[:id])
          snapshot = property.property_transport_snapshot || property.build_property_transport_snapshot
          snapshot.update!(
            provider: payload.fetch(:provider),
            latitude: prop[:lat],
            longitude: prop[:lng],
            flight_data: payload.fetch(:flight_data, {}),
            rail_data: payload.fetch(:rail_data, {}),
            road_data: payload.fetch(:road_data, {}),
            fetched_at: fetched_at,
            status: "ready",
            error_message: nil
          )
        end
      rescue TransportGateway::Error => e
        fallback = nearest_ready_transport_snapshot(anchor[:lat], anchor[:lng])
        if fallback
          fetched_at = Time.current
          properties_in_bucket.each do |prop|
            property = Property.find(prop[:id])
            snapshot = property.property_transport_snapshot || property.build_property_transport_snapshot
            snapshot.update!(
              provider: fallback.provider.presence || TransportGateway::PROVIDER,
              latitude: prop[:lat],
              longitude: prop[:lng],
              flight_data: fallback.flight_data || {},
              rail_data: fallback.rail_data || {},
              road_data: fallback.road_data || {},
              fetched_at: fallback.fetched_at || fetched_at,
              status: "ready",
              error_message: "fallback_from_nearby_snapshot"
            )
          end
          puts "Transport fallback bucket #{anchor[:lat]},#{anchor[:lng]}: #{e.message}"
        else
          errors += properties_in_bucket.length
          properties_in_bucket.each do |prop|
            property = Property.find(prop[:id])
            snapshot = property.property_transport_snapshot || property.build_property_transport_snapshot
            snapshot.update!(
              provider: TransportGateway::PROVIDER,
              latitude: prop[:lat],
              longitude: prop[:lng],
              status: "failed",
              error_message: e.message
            )
          end
          puts "Transport warn bucket #{anchor[:lat]},#{anchor[:lng]}: #{e.message}"
        end
      rescue StandardError => e
        errors += properties_in_bucket.length
        puts "Transport warn bucket #{anchor[:lat]},#{anchor[:lng]}: #{e.class} #{e.message}"
      ensure
        processed += properties_in_bucket.length
        log_throughput("Transport", processed: processed, total: total_properties, errors: errors, started_at: started_at)
      end

      puts "Transport snapshots ready: #{scope.joins(:property_transport_snapshot).where(property_transport_snapshots: { status: 'ready' }).count}"
    end

    if ENV.fetch("RUN_AIR_QUALITY", "1") == "1"
      stations = AirQualityGateway.new.fetch_london_stations
      puts "Air quality stations fetched: #{stations.size}"
      stations.each do |station_data|
        station = AirQualityStation.find_or_initialize_by(external_id: station_data[:external_id])
        station.update!(
          name: station_data[:name],
          latitude: station_data[:latitude],
          longitude: station_data[:longitude]
        )
        AirQualityStationIngestJob.perform_now(station.id, station_data[:timeseries])
        sleep(sleep_seconds) if sleep_seconds.positive?
      rescue StandardError => e
        puts "Air quality warn #{station_data[:external_id]}: #{e.class} #{e.message}"
      end

      stations_with_daqi = AirQualityStation.with_daqi.pluck(:id, :latitude, :longitude)
      if stations_with_daqi.empty?
        puts "Air quality assignments ready: 0 (no stations with DAQI available)"
      else
        air_scope = stage_scope(scope, :air_quality, only_missing: only_missing)
          .where.not(latitude: nil, longitude: nil)
        total_properties = air_scope.count
        processed = 0
        errors = 0
        started_at = Time.current

        air_scope.find_each(batch_size: batch_size) do |property|
          nearest_id = nearest_station_id(stations_with_daqi, property.latitude.to_f, property.longitude.to_f)
          if nearest_id.present?
            property.update_columns(air_quality_station_id: nearest_id)
          else
            errors += 1
          end
          processed += 1
          log_throughput("Air quality assign", processed: processed, total: total_properties, errors: errors, started_at: started_at)
        end
      end
      puts "Air quality assignments ready: #{scope.joins(:air_quality_station).where.not(air_quality_stations: { daqi_index: nil }).count}"
    end
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

  def parse_time(value)
    return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def synthesized_raw_data(record)
    raw_address = (record["raw_address"] || record[:raw_address] || {}).deep_stringify_keys
    raw_property_data = (record["raw_property_data"] || record[:raw_property_data] || {}).deep_stringify_keys
    nearest_stations = Array(record["nearest_stations"] || record[:nearest_stations]).map do |station|
      {
        "name" => station["name"] || station[:name],
        "distance" => station["distance_miles"] || station[:distance_miles],
        "types" => [station["transport_type"] || station[:transport_type]].compact
      }
    end

    {
      "propertyData" => {
        "address" => {
          "displayAddress" => raw_address["display_address"],
          "outcode" => raw_address["outcode"] || record["postcode"] || record[:postcode],
          "town" => raw_address["town"] || record["town"] || record[:town]
        },
        "tags" => raw_property_data["tags"] || [],
        "sizings" => raw_property_data["sizings"] || [],
        "features" => raw_property_data["features"] || {},
        "rooms" => raw_property_data["rooms"] || [],
        "nearestStations" => nearest_stations
      }
    }
  end

  def estimated_walking_minutes(distance_miles)
    distance = distance_miles.to_f
    return nil unless distance.positive?

    ((distance * 1.3 / 3.0) * 60).round
  end

  def set_price_params(url, min, max)
    uri = URI.parse(url)
    params = URI.decode_www_form(uri.query || "").to_h
    params["minPrice"] = min.to_s
    params["maxPrice"] = max.to_s
    uri.query = URI.encode_www_form(params)
    uri.to_s
  end

  def env_enabled?(name, default: true)
    value = ENV.fetch(name, default ? "1" : "0")
    %w[1 true yes y on].include?(value.to_s.strip.downcase)
  end

  def scoped_training_properties(input_path)
    payload = JSON.parse(input_path.read)
    rightmove_ids = payload.fetch("properties", []).map { |record| (record["rightmove_id"] || record[:rightmove_id]).to_s }.uniq
    scope = Property.where(rightmove_id: rightmove_ids).order(:id)

    start_offset = [ENV.fetch("START_OFFSET", "0").to_i, 0].max
    max_properties = [ENV.fetch("MAX_PROPERTIES", "0").to_i, 0].max

    scope = scope.offset(start_offset) if start_offset.positive?
    scope = scope.limit(max_properties) if max_properties.positive?
    scope
  end

  def stage_scope(scope, stage, only_missing:)
    return scope unless only_missing

    case stage
    when :crime
      scope.left_outer_joins(:property_crime_snapshot).where(
        "property_crime_snapshots.id IS NULL OR " \
        "property_crime_snapshots.status <> 'ready' OR " \
        "property_crime_snapshots.avg_monthly_crimes IS NULL"
      )
    when :transport
      scope.left_outer_joins(:property_transport_snapshot).where(
        "property_transport_snapshots.id IS NULL OR property_transport_snapshots.status <> 'ready'"
      )
    when :air_quality
      scope.where(air_quality_station_id: nil)
    when :area_price_growth
      scope.where(area_price_growth_id: nil)
    else
      scope
    end
  end

  def grouped_coordinate_buckets(scope)
    scope
      .pluck(:id, :latitude, :longitude)
      .group_by { |_, lat, lng| [(lat.to_f * 100).round, (lng.to_f * 100).round] }
      .transform_values do |rows|
        rows.map { |id, lat, lng| { id: id, lat: lat.to_f, lng: lng.to_f } }
      end
  end

  def log_throughput(stage, processed:, total:, errors:, started_at:)
    return if total <= 0
    return unless (processed % 25).zero? || processed == total

    elapsed_minutes = [(Time.current - started_at) / 60.0, 1.0 / 60].max
    rate = processed / elapsed_minutes
    remaining = [total - processed, 0].max
    eta = remaining.zero? ? 0.0 : (remaining / [rate, 0.001].max)
    puts "#{stage} progress #{processed}/#{total} | errors=#{errors} | rate=#{rate.round(1)} props/min | eta=#{eta.round(1)} min"
  end

  def nearest_station_id(stations, lat, lon)
    stations.min_by { |_id, slat, slon| Math.sqrt((lat - slat.to_f)**2 + (lon - slon.to_f)**2) }&.first
  end

  def nearest_ready_transport_snapshot(lat, lng, tolerance: 0.02)
    PropertyTransportSnapshot
      .where(status: "ready")
      .where(latitude: (lat.to_f - tolerance)..(lat.to_f + tolerance))
      .where(longitude: (lng.to_f - tolerance)..(lng.to_f + tolerance))
      .order(fetched_at: :desc)
      .first
  end
end
