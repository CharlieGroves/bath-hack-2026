class PropertyLocationSearch
  DEFAULT_TRAVEL_TIME = 15.minutes.to_i
  DEFAULT_TRANSPORTATION_TYPE = "driving".freeze
  ALLOWED_TRANSPORTATION_TYPES = %w[driving walking cycling public_transport].freeze
  MIN_TRAVEL_TIME = 60
  MAX_TRAVEL_TIME = 7_200

  class Error < StandardError; end
  class InvalidQuery < Error; end
  class InvalidTransportationType < Error; end
  class InvalidTravelTime < Error; end

  def initialize(scope: Property.all,
                 geocoder: TravelTimeGeocoder.new,
                 travel_time_gateway: TravelTimeGateway.new)
    @scope = scope
    @geocoder = geocoder
    @travel_time_gateway = travel_time_gateway
  end

  def call(query:, transportation_type: DEFAULT_TRANSPORTATION_TYPE, travel_time: DEFAULT_TRAVEL_TIME, latitude: nil, longitude: nil)
    normalized_query = query.to_s.strip
    raise InvalidQuery, "Query can't be blank" if normalized_query.blank?

    normalized_transportation_type = normalize_transportation_type(transportation_type)
    normalized_travel_time = normalize_travel_time(travel_time)

    location = if latitude.present? && longitude.present?
                 { latitude: latitude.to_f, longitude: longitude.to_f, label: normalized_query }
               else
                 @geocoder.search!(normalized_query)
               end
    isochrone = @travel_time_gateway.isochrone!(
      latitude: location.fetch(:latitude),
      longitude: location.fetch(:longitude),
      transportation_type: normalized_transportation_type,
      travel_time: normalized_travel_time
    )
    properties = filter_properties(
      @scope.with_coordinates.within_bounding_box(isochrone.fetch(:bounding_box)),
      isochrone.fetch(:shells)
    )

    {
      query: normalized_query,
      location: location,
      transportation_type: normalized_transportation_type,
      travel_time_seconds: normalized_travel_time,
      bounding_box: isochrone.fetch(:bounding_box),
      isochrone_shells: isochrone.fetch(:shells),
      properties: properties
    }
  end

  private

  def filter_properties(properties, shells)
    properties.select do |property|
      latitude = property.latitude&.to_f
      longitude = property.longitude&.to_f
      next false if latitude.blank? || longitude.blank?

      point_inside_isochrone?(latitude, longitude, shells)
    end
  end

  def point_inside_isochrone?(latitude, longitude, shells)
    shells.any? do |shell|
      next false if shell.length < 3

      point_on_boundary?(latitude, longitude, shell) || point_in_polygon?(latitude, longitude, shell)
    end
  end

  def point_in_polygon?(latitude, longitude, shell)
    inside = false
    previous = shell.last

    shell.each do |current|
      current_lat = current.fetch(:latitude)
      current_lng = current.fetch(:longitude)
      previous_lat = previous.fetch(:latitude)
      previous_lng = previous.fetch(:longitude)

      intersects = ((current_lat > latitude) != (previous_lat > latitude)) &&
        (longitude < ((previous_lng - current_lng) * (latitude - current_lat) / (previous_lat - current_lat)) + current_lng)

      inside = !inside if intersects
      previous = current
    end

    inside
  end

  def point_on_boundary?(latitude, longitude, shell)
    shell.each_cons(2).any? do |start_point, end_point|
      point_on_segment?(latitude, longitude, start_point, end_point)
    end || point_on_segment?(latitude, longitude, shell.last, shell.first)
  end

  def point_on_segment?(latitude, longitude, start_point, end_point)
    start_lat = start_point.fetch(:latitude)
    start_lng = start_point.fetch(:longitude)
    end_lat = end_point.fetch(:latitude)
    end_lng = end_point.fetch(:longitude)

    cross_product = ((latitude - start_lat) * (end_lng - start_lng)) - ((longitude - start_lng) * (end_lat - start_lat))
    return false unless cross_product.abs < 1e-9

    lat_within_segment = latitude.between?([start_lat, end_lat].min, [start_lat, end_lat].max)
    lng_within_segment = longitude.between?([start_lng, end_lng].min, [start_lng, end_lng].max)

    lat_within_segment && lng_within_segment
  end

  def normalize_transportation_type(transportation_type)
    normalized_transportation_type = transportation_type.to_s.presence || DEFAULT_TRANSPORTATION_TYPE
    return normalized_transportation_type if ALLOWED_TRANSPORTATION_TYPES.include?(normalized_transportation_type)

    raise InvalidTransportationType,
          "Transportation type must be one of: #{ALLOWED_TRANSPORTATION_TYPES.join(', ')}"
  end

  def normalize_travel_time(travel_time)
    normalized_travel_time = travel_time.to_i
    return normalized_travel_time if normalized_travel_time.between?(MIN_TRAVEL_TIME, MAX_TRAVEL_TIME)

    raise InvalidTravelTime,
          "Travel time must be between #{MIN_TRAVEL_TIME / 60} and #{MAX_TRAVEL_TIME / 60} minutes"
  end
end
