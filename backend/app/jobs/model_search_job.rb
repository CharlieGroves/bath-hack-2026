# Processes a natural-language property search prompt via GPT-4o-mini.
#
# Flow:
#   1. Send prompt to OpenAI with a structured system prompt
#   2. Parse the JSON filter parameters from the response
#   3. Apply those filters to the Property table
#   4. Store the ordered property IDs on the ModelSearch record
#
# The ModelSearch status transitions: pending → complete | failed
# Frontend polls GET /api/v1/model_searches/:id to check status.
class ModelSearchJob < ApplicationJob
  queue_as :default

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are a property search assistant for a London real estate platform.

    Given a natural-language description of what a user is looking for, extract
    structured search filters and return them as a JSON object.

    The JSON object may contain any of the following keys (all optional):

    - min_price         (Integer) minimum price in pence (e.g. 30000000 = £300,000)
    - max_price         (Integer) maximum price in pence
    - min_beds          (Integer) minimum bedrooms
    - max_beds          (Integer) maximum bedrooms
    - property_type     (String) one of: flat, terraced, semi_detached, detached, bungalow, land, other
    - tenure            (String) one of: freehold, leasehold, share_of_freehold
    - status            (String) one of: active, under_offer, sold, let
    - max_daqi          (Integer 1–10) maximum air quality index — lower is better air quality
    - max_flood_risk_band (Integer 1–4) maximum flood risk: 1=Very Low, 2=Low, 3=Medium, 4=High
    - max_road_noise_lden  (Float) maximum road noise in dB(A) Lden
    - max_rail_noise_lden  (Float) maximum rail noise in dB(A) Lden
    - max_flight_noise_lden (Float) maximum flight noise in dB(A) Lden
    - sort              (String) one of: price_asc, price_desc, newest - default newest

    Rules:
    - Prices must always be in pence (multiply £ amount by 100)
    - If the user says "quiet", set max_road_noise_lden to 55 and max_rail_noise_lden to 55
    - If the user says "good air quality", set max_daqi to 4
    - If the user says "low flood risk", set max_flood_risk_band to 2
    - Only include keys that are relevant to the user's request
    - Return ONLY the JSON object, no explanation

    Example input: "2 bed flat under £400k, freehold, good air quality"
    Example output: {"min_beds":2,"max_beds":2,"property_type":"flat","max_price":40000000,"tenure":"freehold","max_daqi":4}
  PROMPT

  def perform(model_search_id)
    search = ModelSearch.find_by(id: model_search_id)
    return unless search&.pending?

    # 1. Call OpenAI
    raw = Gateways::OpenAiGateway.new.chat(
      system: SYSTEM_PROMPT,
      user:   search.prompt,
      format: :json
    )

    # 2. Parse filters
    filters = JSON.parse(raw)

    # 3. Apply filters to Property
    properties = apply_filters(Property.all, filters)

    # 4. Apply sort
    properties = apply_sort(properties, filters["sort"])

    # 5. Store result
    ids = properties.limit(200).pluck(:id)
    search.mark_complete!(ids, filters)

    Rails.logger.info("[ModelSearchJob] search=#{model_search_id} → #{ids.size} results, filters=#{filters.inspect}")

  rescue Gateways::OpenAiGateway::ConfigError => e
    Rails.logger.error("[ModelSearchJob] Config error: #{e.message}")
    search&.mark_failed!("Service not configured: #{e.message}")
  rescue Gateways::OpenAiGateway::Error => e
    Rails.logger.error("[ModelSearchJob] OpenAI error: #{e.message}")
    search&.mark_failed!(e.message)
    raise
  rescue JSON::ParserError => e
    Rails.logger.error("[ModelSearchJob] Invalid JSON from OpenAI: #{e.message}")
    search&.mark_failed!("Could not parse search parameters")
  rescue => e
    Rails.logger.error("[ModelSearchJob] Unexpected error: #{e.message}")
    search&.mark_failed!(e.message)
    raise
  end

  private

  def apply_filters(scope, filters)
    scope = scope.where(status: filters["status"])                         if filters["status"].present?
    scope = scope.where(property_type: filters["property_type"])           if filters["property_type"].present?
    scope = scope.where(tenure: filters["tenure"])                         if filters["tenure"].present?
    scope = scope.min_price(filters["min_price"].to_i)                    if filters["min_price"].present?
    scope = scope.max_price(filters["max_price"].to_i)                    if filters["max_price"].present?
    scope = scope.min_beds(filters["min_beds"].to_i)                      if filters["min_beds"].present?
    scope = scope.max_beds(filters["max_beds"].to_i)                      if filters["max_beds"].present?
    scope = scope.max_daqi(filters["max_daqi"].to_i)                      if filters["max_daqi"].present?
    scope = scope.max_flood_risk_band(filters["max_flood_risk_band"].to_i) if filters["max_flood_risk_band"].present?
    scope = scope.max_road_noise_lden(filters["max_road_noise_lden"].to_f)   if filters["max_road_noise_lden"].present?
    scope = scope.max_rail_noise_lden(filters["max_rail_noise_lden"].to_f)   if filters["max_rail_noise_lden"].present?
    scope = scope.max_flight_noise_lden(filters["max_flight_noise_lden"].to_f) if filters["max_flight_noise_lden"].present?
    scope
  end

  def apply_sort(scope, sort)
    case sort
    when "price_asc"  then scope.by_price_asc
    when "price_desc" then scope.by_price_desc
    else scope.by_newest
    end
  end
end
