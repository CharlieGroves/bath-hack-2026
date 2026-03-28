require_relative "gateways/british_national_grid"
require_relative "gateways/england_noise_sampler"
require_relative "gateways/england_flight_noise_gateway"
require_relative "gateways/england_rail_noise_gateway"
require_relative "gateways/england_road_noise_gateway"

class TransportGateway
  class Error < StandardError; end
  PROVIDER = "england_noise_data".freeze

  def initialize(rail_gateway: EnglandRailNoiseGateway.new,
                 flight_gateway: EnglandFlightNoiseGateway.new,
                 road_gateway: EnglandRoadNoiseGateway.new)
    @rail_gateway = rail_gateway
    @flight_gateway = flight_gateway
    @road_gateway = road_gateway
  end

  def fetch(latitude:, longitude:)
    {
      provider: PROVIDER,
      flight_data: @flight_gateway.fetch(latitude: latitude, longitude: longitude),
      rail_data: @rail_gateway.fetch(latitude: latitude, longitude: longitude),
      road_data: @road_gateway.fetch(latitude: latitude, longitude: longitude)
    }
  end
end
