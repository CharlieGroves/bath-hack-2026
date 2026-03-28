class EnglandRailNoiseGateway
  def initialize(sampler: EnglandNoiseSampler.new(
    cache_key_prefix: "rail",
    dataset_id: "3fb3c2d7-292c-4e0a-bd5b-d8e4e1fe2947",
    coverage_prefix: "Rail_Noise_",
    coverage_suffix: "_England_Round_4_All",
    metrics: {
      "laeq06hr" => "LAeq06hr",
      "laeq16hr" => "LAeq16hr",
      "laeq18hr" => "LAeq18hr",
      "lday" => "Lday",
      "lden" => "Lden",
      "leve" => "Leve",
      "lnight" => "Lnight"
    },
    origin_easting: 82650.0,
    origin_northing: 657600.0,
    bounds: {
      min_easting: 82645.0,
      min_northing: 5335.0,
      max_easting: 655995.0,
      max_northing: 657605.0
    }
  ))
    @sampler = sampler
  end

  def fetch(latitude:, longitude:)
    @sampler.fetch(latitude: latitude, longitude: longitude)
  end
end
