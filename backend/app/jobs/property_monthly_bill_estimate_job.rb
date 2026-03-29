class PropertyMonthlyBillEstimateJob < ApplicationJob
  queue_as :default

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You estimate rough monthly household bills for UK residential properties.

    Return strictly valid JSON with this shape:
    {
      "estimated_total_monthly_pence": Integer,
      "confidence": "low" | "medium" | "high",
      "assumptions": [String],
      "breakdown": {
        "council_tax_monthly_pence": Integer | null,
        "energy_monthly_pence": Integer | null,
        "water_monthly_pence": Integer | null,
        "broadband_monthly_pence": Integer | null,
        "service_charge_monthly_pence": Integer | null,
        "insurance_monthly_pence": Integer | null,
        "maintenance_monthly_pence": Integer | null,
        "other_monthly_pence": Integer | null
      }
    }

    Rules:
    - Use only the supplied property data.
    - Output all money values as monthly pence integers.
    - Keep assumptions concise (max 6 items).
    - Never include markdown or explanatory prose outside JSON.
  PROMPT

  BREAKDOWN_KEYS = %w[
    council_tax_monthly_pence
    energy_monthly_pence
    water_monthly_pence
    broadband_monthly_pence
    service_charge_monthly_pence
    insurance_monthly_pence
    maintenance_monthly_pence
    other_monthly_pence
  ].freeze

  CONFIDENCE_LEVELS = %w[low medium high].freeze

  def perform(property_id)
    property = Property
      .includes(:property_transport_snapshot, :property_crime_snapshot, :air_quality_station, :borough, :property_nearest_stations)
      .find_by(id: property_id)
    return unless property

    estimate = property.property_monthly_bill_estimate || property.build_property_monthly_bill_estimate
    raw = Gateways::OpenAiGateway.new.chat(
      system: SYSTEM_PROMPT,
      user: estimate_prompt(property),
      format: :json
    )
    parsed = JSON.parse(raw)
    normalized = normalize_estimate(parsed)

    estimate.update!(
      provider: "openai",
      model_name: Gateways::OpenAiGateway::MODEL,
      status: "ready",
      estimated_total_monthly_pence: normalized.fetch(:estimated_total_monthly_pence),
      confidence: normalized[:confidence],
      assumptions: normalized[:assumptions],
      breakdown: normalized.fetch(:breakdown),
      raw_payload: parsed,
      fetched_at: Time.current,
      error_message: nil
    )
  rescue JSON::ParserError => e
    save_failure(property, "Invalid JSON from OpenAI: #{e.message}") if property
  rescue Gateways::OpenAiGateway::ConfigError => e
    save_failure(property, e.message) if property
  rescue Gateways::OpenAiGateway::Error => e
    save_failure(property, e.message) if property
  end

  private

  def estimate_prompt(property)
    <<~PROMPT
      Estimate rough monthly household bills for this property.
      Use this JSON as the full available context:

      #{JSON.pretty_generate(property_context(property))}
    PROMPT
  end

  def property_context(property)
    {
      property: {
        rightmove_id: property.rightmove_id,
        title: property.title,
        description_excerpt: property.description.to_s.first(1_000),
        address_line_1: property.address_line_1,
        town: property.town,
        postcode: property.postcode,
        price_pence: property.price_pence,
        property_type: property.property_type,
        bedrooms: property.bedrooms,
        bathrooms: property.bathrooms,
        size_sqft: property.size_sqft,
        tenure: property.tenure,
        lease_years_remaining: property.lease_years_remaining,
        epc_rating: property.epc_rating,
        council_tax_band: property.council_tax_band,
        service_charge_annual_pence: property.service_charge_annual_pence,
        utilities_text: property.utilities_text,
        parking_text: property.parking_text,
        key_features: Array(property.key_features).first(12)
      },
      enrichment: {
        transport_noise_lden: transport_noise_payload(property.property_transport_snapshot),
        avg_monthly_crimes: property.property_crime_snapshot&.avg_monthly_crimes,
        air_quality_daqi: property.air_quality_station&.daqi_index,
        borough: {
          name: property.borough&.name,
          nte_score: property.borough&.nte_score
        },
        nearest_stations: property.property_nearest_stations
          .sort_by(&:distance_miles)
          .first(3)
          .map { |station|
            {
              name: station.name,
              walking_minutes: station.walking_minutes,
              distance_miles: station.distance_miles
            }
          }
      }
    }
  end

  def transport_noise_payload(snapshot)
    return {} unless snapshot

    {
      road_lden: snapshot.road_data&.dig("metrics", "lden"),
      rail_lden: snapshot.rail_data&.dig("metrics", "lden"),
      flight_lden: snapshot.flight_data&.dig("metrics", "lden")
    }
  end

  def normalize_estimate(parsed)
    breakdown_raw = parsed["breakdown"].is_a?(Hash) ? parsed["breakdown"] : {}
    breakdown = BREAKDOWN_KEYS.index_with { |key| clamp_pence(breakdown_raw[key]) }
    inferred_total = breakdown.values.compact.sum
    stated_total = clamp_pence(parsed["estimated_total_monthly_pence"])

    {
      estimated_total_monthly_pence: stated_total || inferred_total,
      confidence: normalize_confidence(parsed["confidence"]),
      assumptions: normalize_assumptions(parsed["assumptions"]),
      breakdown: breakdown
    }
  end

  def clamp_pence(value)
    return nil if value.nil?

    numeric = Float(value, exception: false)
    return nil unless numeric

    [[numeric.round, 0].max, 50_000_000].min
  end

  def normalize_confidence(value)
    confidence = value.to_s.strip.downcase
    CONFIDENCE_LEVELS.include?(confidence) ? confidence : "medium"
  end

  def normalize_assumptions(value)
    items = Array(value).map(&:to_s).map(&:strip).reject(&:blank?).first(6)
    return nil if items.empty?

    items.join(" | ")
  end

  def save_failure(property, message)
    estimate = property.property_monthly_bill_estimate || property.build_property_monthly_bill_estimate
    estimate.update!(
      provider: "openai",
      model_name: Gateways::OpenAiGateway::MODEL,
      status: "failed",
      error_message: message
    )
  end
end
