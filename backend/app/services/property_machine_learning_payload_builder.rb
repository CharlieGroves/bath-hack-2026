class PropertyMachineLearningPayloadBuilder
  def initialize(property)
    @property = property
  end

  def as_json
    {
      id: @property.id,
      rightmove_id: @property.rightmove_id,
      title: @property.title,
      description: @property.description,
      address_line_1: @property.address_line_1,
      town: @property.town,
      postcode: @property.postcode,
      price_pence: @property.price_pence,
      price_per_sqft_pence: @property.price_per_sqft_pence,
      bedrooms: @property.bedrooms,
      bathrooms: @property.bathrooms,
      size_sqft: @property.size_sqft,
      property_type: @property.property_type,
      tenure: @property.tenure,
      lease_years_remaining: @property.lease_years_remaining,
      service_charge_annual_pence: @property.service_charge_annual_pence,
      epc_rating: @property.epc_rating,
      council_tax_band: @property.council_tax_band,
      utilities_text: @property.utilities_text,
      parking_text: @property.parking_text,
      latitude: @property.latitude&.to_f,
      longitude: @property.longitude&.to_f,
      has_floor_plan: @property.has_floor_plan,
      has_virtual_tour: @property.has_virtual_tour,
      status: @property.status,
      listed_at: @property.listed_at&.iso8601,
      photo_urls: @property.photo_urls,
      key_features: @property.key_features,
      photo_count: @property.photo_urls.size,
      key_feature_count: @property.key_features.size,
      raw_address: {
        display_address: @property.raw_data&.dig("propertyData", "address", "displayAddress"),
        outcode: @property.raw_data&.dig("propertyData", "address", "outcode"),
        town: @property.raw_data&.dig("propertyData", "address", "town")
      },
      raw_property_data: {
        tags: @property.raw_data&.dig("propertyData", "tags") || [],
        sizings: @property.raw_data&.dig("propertyData", "sizings") || [],
        features: @property.raw_data&.dig("propertyData", "features") || {},
        rooms: @property.raw_data&.dig("propertyData", "rooms") || []
      },
      area_price_growth: area_price_growth_payload,
      borough: borough_payload,
      estate_agent: estate_agent_payload,
      noise: noise_payload,
      crime: crime_payload,
      air_quality: air_quality_payload,
      nearest_stations: nearest_stations_payload
    }
  end

  private

  def area_price_growth_payload
    return nil unless table_available?("area_price_growths")

    return nil unless @property.area_price_growth

    {
      area_slug: @property.area_price_growth.area_slug,
      area_name: @property.area_price_growth.area_name,
      yearly_growth_data: @property.area_price_growth.yearly_growth_data
    }
  end

  def borough_payload
    return nil unless table_available?("boroughs")

    return nil unless @property.borough

    {
      name: @property.borough.name,
      nte_score: @property.borough.nte_score,
      life_satisfaction_score: @property.borough.life_satisfaction_score,
      happiness_score: @property.borough.happiness_score,
      anxiety_score: @property.borough.anxiety_score
    }
  end

  def estate_agent_payload
    return nil unless table_available?("estate_agents")

    return nil unless @property.estate_agent

    {
      display_name: @property.estate_agent.display_name,
      rating: @property.estate_agent.rating&.to_f
    }
  end

  def noise_payload
    return nil unless table_available?("property_transport_snapshots")

    snapshot = @property.property_transport_snapshot
    return nil unless snapshot

    {
      provider: snapshot.provider,
      status: snapshot.status,
      fetched_at: snapshot.fetched_at,
      flight_data: snapshot.flight_data,
      rail_data: snapshot.rail_data,
      road_data: snapshot.road_data
    }
  end

  def crime_payload
    return nil unless table_available?("property_crime_snapshots")

    snapshot = @property.property_crime_snapshot
    return nil unless snapshot

    {
      status: snapshot.status,
      avg_monthly_crimes: snapshot.avg_monthly_crimes,
      fetched_at: snapshot.fetched_at
    }
  end

  def air_quality_payload
    return nil unless table_available?("air_quality_stations")

    station = @property.air_quality_station
    return nil unless station

    {
      daqi_index: station.daqi_index,
      daqi_band: station.daqi_band,
      station_name: station.name
    }
  end

  def nearest_stations_payload
    return [] unless table_available?("property_nearest_stations")

    @property.property_nearest_stations
      .sort_by { |station| station.distance_miles || Float::INFINITY }
      .map do |station|
        {
          name: station.name,
          distance_miles: station.distance_miles&.to_f,
          walking_minutes: station.walking_minutes,
          transport_type: station.transport_type
        }
      end
  end

  def table_available?(table_name)
    ActiveRecord::Base.connection.data_source_exists?(table_name)
  rescue StandardError
    false
  end
end
