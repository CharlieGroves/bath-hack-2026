class EnglandRoadNoiseGateway
  def initialize(sampler: EnglandNoiseSampler.new(
    cache_key_prefix: "road",
    dataset_id: "562c9d56-7c2d-4d42-83bb-578d6e97a517",
    coverage_prefix: "Road_Noise_",
    coverage_suffix: "_England_Round_4_All",
    metrics: {
      "laeq16hr" => "LAeq16hr",
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
