class EnglandFlightNoiseGateway
  def initialize(sampler: EnglandNoiseSampler.new(
    cache_key_prefix: "airport",
    dataset_id: "dac9cba4-abe7-43bd-b8e9-8a83da52edd8",
    coverage_prefix: "Airport_Noise_ALL_",
    metrics: {
      "laeq16hr" => "LAeq16hr",
      "lday" => "Lday",
      "lden" => "Lden",
      "leve" => "Leve",
      "lnight" => "Lnight"
    },
    origin_easting: 333490.0,
    origin_northing: 574280.0,
    bounds: {
      min_easting: 333485.0,
      min_northing: 93815.0,
      max_easting: 594465.0,
      max_northing: 574285.0
    }
  ))
    @sampler = sampler
  end

  def fetch(latitude:, longitude:)
    @sampler.fetch(latitude: latitude, longitude: longitude)
  end
end
