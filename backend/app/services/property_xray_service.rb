class PropertyXrayService
  WALKING_BANDS = [5, 10, 15].freeze
  EARTH_RADIUS_KM = 6371.0

  def initialize(property, travel_time_gateway: TravelTimeGateway.new, overpass_gateway: OverpassGateway.new)
    @property = property
    @travel_time_gateway = travel_time_gateway
    @overpass_gateway = overpass_gateway
  end

  def call
    lat = @property.latitude.to_f
    lng = @property.longitude.to_f

    # Fire all external requests in parallel — 3x TravelTime + 1x Overpass
    isochrone_threads = WALKING_BANDS.map do |minutes|
      Thread.new do
        begin
          result = @travel_time_gateway.isochrone!(
            latitude: lat,
            longitude: lng,
            travel_time: minutes * 60,
            transportation_type: "walking"
          )
          { minutes: minutes, shells: result.fetch(:shells) }
        rescue TravelTimeGateway::Error
          nil
        end
      end
    end

    pois_thread = Thread.new do
      raw = @overpass_gateway.nearby_pois(latitude: lat, longitude: lng, radius_metres: 1000)
      raw.map do |poi|
        poi.merge(walk_minutes: estimate_walk_minutes(lat, lng, poi[:latitude], poi[:longitude]))
      end.sort_by { |poi| poi[:walk_minutes] }
    end

    isochrones = isochrone_threads.map(&:value).compact
    pois       = pois_thread.value

    { isochrones: isochrones, pois: pois }
  end

  private

  # Haversine straight-line distance * 1.3 detour factor / 3 mph walking speed
  def estimate_walk_minutes(from_lat, from_lng, to_lat, to_lng)
    dlat = (to_lat - from_lat) * Math::PI / 180
    dlng = (to_lng - from_lng) * Math::PI / 180
    a = Math.sin(dlat / 2)**2 +
        Math.cos(from_lat * Math::PI / 180) * Math.cos(to_lat * Math::PI / 180) *
        Math.sin(dlng / 2)**2
    km = 2 * EARTH_RADIUS_KM * Math.asin(Math.sqrt(a))
    (km * 1.3 / (3.0 * 1.60934) * 60).round
  end
end
