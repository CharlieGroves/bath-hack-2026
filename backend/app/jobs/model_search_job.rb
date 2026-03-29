# Processes a natural-language property search prompt via GPT-4o-mini.
#
# Flow:
#   1. Compute live percentile thresholds from the database
#   2. Build a system prompt that embeds those thresholds as named rules
#   3. Send the prompt to OpenAI and parse the JSON filter parameters
#   4. Apply those filters to the Property table
#   5. Store the ordered property IDs on the ModelSearch record
#
# The ModelSearch status transitions: pending → complete | failed
# Frontend polls GET /api/v1/model_searches/:id to check status.
class ModelSearchJob < ApplicationJob
  queue_as :default

  PROMPT_TEMPLATE = <<~PROMPT.freeze
    You are a property search assistant for a London real estate platform.

    Given a natural-language description of what a user is looking for, extract
    structured search filters and return them as a JSON object.

    The JSON object may contain any of the following keys (all optional):

    Price & size:
    - min_price           (Integer) minimum price in pence (e.g. 30000000 = £300,000)
    - max_price           (Integer) maximum price in pence
    - min_price_per_sqft  (Integer) minimum price per sqft in pence
    - max_price_per_sqft  (Integer) maximum price per sqft in pence
    - min_sqft            (Integer) minimum internal size in square feet
    - min_beds            (Integer) minimum bedrooms
    - max_beds            (Integer) maximum bedrooms
    - min_bathrooms       (Integer) minimum bathrooms

    Property details:
    - property_type       (String) one of: flat, terraced, semi_detached, detached, bungalow, land, other
                          IMPORTANT: only set this if the user specifies a precise property type.
                          "house" or "houses" is NOT a valid type — do NOT set property_type for generic house requests.
                          Use terraced/semi_detached/detached/bungalow only when the user explicitly names one of those.
    - tenure              (String) one of: freehold, leasehold, share_of_freehold
    - status              (String) one of: active, under_offer, sold, let
    - is_shared_ownership (Boolean) true for shared-ownership / percentage-share listings
    - min_epc_rating      (String) minimum EPC band — one of: A, B, C, D, E, F, G (A is best)

    Environment & safety:
    - max_daqi              (Integer 1–10) maximum air quality index — lower is better
    - max_flood_risk_band   (Integer 1–4) maximum flood risk band: 1=Very Low, 2=Low, 3=Medium, 4=High
    - max_crime_rate        (Float) maximum average monthly crimes near the property
    - max_road_noise_lden   (Float) maximum road noise in dB(A) Lden
    - max_rail_noise_lden   (Float) maximum rail noise in dB(A) Lden
    - max_flight_noise_lden (Float) maximum flight noise in dB(A) Lden

    Borough wellbeing scores (all normalised 0–1, higher = better):
    - min_life_satisfaction (Float 0–1) minimum borough life-satisfaction score
    - min_happiness         (Float 0–1) minimum borough happiness score
    - max_anxiety           (Float 0–1) maximum borough anxiety score (lower = less anxious)
    - min_nte_score         (Float 0–1) minimum night-time economy score (higher = more vibrant nightlife)
    - max_nte_score         (Float 0–1) maximum night-time economy score (lower = quieter area)

    Sorting:
    - sort                  (String) one of: price_asc, price_desc, newest — default newest

    The following thresholds are computed from the actual distribution of data in this platform's database.
    Use them when the user's query matches the corresponding concept:

    %<rules>s

    Additional rules:
    - Prices must always be in pence (multiply £ amount by 100)
    - Price per sqft must also be in pence (e.g. £500/sqft = 50000)
    - Only include keys that are relevant to the user's request
    - Return ONLY the JSON object, no explanation

    Example input: "2 bed flat under £400k, freehold, good air quality, safe area"
    Example output: {"min_beds":2,"max_beds":2,"property_type":"flat","max_price":40000000,"tenure":"freehold","max_daqi":%<example_daqi>s,"max_crime_rate":%<example_crime>s}
  PROMPT

  def perform(model_search_id)
    search = ModelSearch.find_by(id: model_search_id)
    return unless search&.pending?

    # 1. Compute live thresholds from the database
    thresholds = compute_thresholds

    # 2. Call OpenAI with a prompt that embeds the live thresholds
    raw = Gateways::OpenAiGateway.new.chat(
      system: build_system_prompt(thresholds),
      user:   search.prompt,
      format: :json
    )

    # 3. Parse filters
    filters = JSON.parse(raw)

    # 4. Apply filters to Property
    properties = apply_filters(Property.all, filters)

    # 5. Apply sort
    properties = apply_sort(properties, filters["sort"])

    # 6. Store result
    ids = properties.limit(200).pluck(:id)
    search.mark_complete!(ids, filters)

    Rails.logger.info("[ModelSearchJob] search=#{model_search_id} → #{ids.size} results, filters=#{filters.inspect}, thresholds=#{thresholds.inspect}")

  rescue JSON::ParserError => e
    Rails.logger.error("[ModelSearchJob] Invalid JSON from OpenAI: #{e.message}")
    search&.mark_failed!("Could not parse search parameters")
  rescue => e
    # Evaluating Gateways::OpenAiGateway::ConfigError/Error in rescue clauses can itself
    # raise NameError if the constant isn't resolved yet, swallowing mark_failed!.
    # Inspect class name as a string instead to safely distinguish error types.
    klass = e.class.name.to_s
    Rails.logger.error("[ModelSearchJob] #{klass}: #{e.message}")

    if klass.end_with?("::ConfigError")
      search&.mark_failed!("Search service not configured — contact support")
    elsif klass.end_with?("::Error")
      search&.mark_failed!(e.message)
      raise
    else
      search&.mark_failed!(e.message)
      raise
    end
  end

  private

  # Queries PostgreSQL percentile_cont to derive P25/P50/P75 thresholds from live data
  # for every continuous field used in natural-language rules. Returns a nested hash:
  #   { crime: { p25: x, p50: y, p75: z }, daqi: { … }, … }
  # Any field with no data returns nil and is omitted from the prompt.
  def compute_thresholds
    conn = ActiveRecord::Base.connection

    # Run one query per field, fetching all three percentiles at once via ARRAY agg
    fetch = ->(sql) {
      row = conn.select_one(sql)
      return nil unless row
      { p25: row["p25"]&.to_f&.round(4),
        p50: row["p50"]&.to_f&.round(4),
        p75: row["p75"]&.to_f&.round(4) }
    }

    {
      crime: fetch.call(<<~SQL),
        SELECT
          percentile_cont(0.25) WITHIN GROUP (ORDER BY avg_monthly_crimes) AS p25,
          percentile_cont(0.50) WITHIN GROUP (ORDER BY avg_monthly_crimes) AS p50,
          percentile_cont(0.75) WITHIN GROUP (ORDER BY avg_monthly_crimes) AS p75
        FROM property_crime_snapshots
        WHERE status = 'ready' AND avg_monthly_crimes IS NOT NULL
      SQL

      daqi: fetch.call(<<~SQL),
        SELECT
          percentile_cont(0.25) WITHIN GROUP (ORDER BY daqi_index) AS p25,
          percentile_cont(0.50) WITHIN GROUP (ORDER BY daqi_index) AS p50,
          percentile_cont(0.75) WITHIN GROUP (ORDER BY daqi_index) AS p75
        FROM air_quality_stations
        WHERE daqi_index IS NOT NULL
      SQL

      road_noise: fetch.call(<<~SQL),
        SELECT
          percentile_cont(0.25) WITHIN GROUP (ORDER BY CAST(road_data -> 'metrics' ->> 'lden' AS NUMERIC)) AS p25,
          percentile_cont(0.50) WITHIN GROUP (ORDER BY CAST(road_data -> 'metrics' ->> 'lden' AS NUMERIC)) AS p50,
          percentile_cont(0.75) WITHIN GROUP (ORDER BY CAST(road_data -> 'metrics' ->> 'lden' AS NUMERIC)) AS p75
        FROM property_transport_snapshots
        WHERE status = 'ready' AND road_data -> 'metrics' ->> 'lden' IS NOT NULL
      SQL

      rail_noise: fetch.call(<<~SQL),
        SELECT
          percentile_cont(0.25) WITHIN GROUP (ORDER BY CAST(rail_data -> 'metrics' ->> 'lden' AS NUMERIC)) AS p25,
          percentile_cont(0.50) WITHIN GROUP (ORDER BY CAST(rail_data -> 'metrics' ->> 'lden' AS NUMERIC)) AS p50,
          percentile_cont(0.75) WITHIN GROUP (ORDER BY CAST(rail_data -> 'metrics' ->> 'lden' AS NUMERIC)) AS p75
        FROM property_transport_snapshots
        WHERE status = 'ready' AND rail_data -> 'metrics' ->> 'lden' IS NOT NULL
      SQL

      flight_noise: fetch.call(<<~SQL),
        SELECT
          percentile_cont(0.25) WITHIN GROUP (ORDER BY CAST(flight_data -> 'metrics' ->> 'lden' AS NUMERIC)) AS p25,
          percentile_cont(0.50) WITHIN GROUP (ORDER BY CAST(flight_data -> 'metrics' ->> 'lden' AS NUMERIC)) AS p50,
          percentile_cont(0.75) WITHIN GROUP (ORDER BY CAST(flight_data -> 'metrics' ->> 'lden' AS NUMERIC)) AS p75
        FROM property_transport_snapshots
        WHERE status = 'ready' AND flight_data -> 'metrics' ->> 'lden' IS NOT NULL
      SQL

      # Borough scores are computed only over boroughs that actually have properties
      # so percentiles reflect what is achievable within the current listing set.
      life_satisfaction: fetch.call(<<~SQL),
        SELECT
          percentile_cont(0.25) WITHIN GROUP (ORDER BY b.life_satisfaction_score) AS p25,
          percentile_cont(0.50) WITHIN GROUP (ORDER BY b.life_satisfaction_score) AS p50,
          percentile_cont(0.75) WITHIN GROUP (ORDER BY b.life_satisfaction_score) AS p75
        FROM boroughs b
        WHERE b.life_satisfaction_score IS NOT NULL
          AND EXISTS (SELECT 1 FROM properties p WHERE p.borough_id = b.id)
      SQL

      happiness: fetch.call(<<~SQL),
        SELECT
          percentile_cont(0.25) WITHIN GROUP (ORDER BY b.happiness_score) AS p25,
          percentile_cont(0.50) WITHIN GROUP (ORDER BY b.happiness_score) AS p50,
          percentile_cont(0.75) WITHIN GROUP (ORDER BY b.happiness_score) AS p75
        FROM boroughs b
        WHERE b.happiness_score IS NOT NULL
          AND EXISTS (SELECT 1 FROM properties p WHERE p.borough_id = b.id)
      SQL

      anxiety: fetch.call(<<~SQL),
        SELECT
          percentile_cont(0.25) WITHIN GROUP (ORDER BY b.anxiety_score) AS p25,
          percentile_cont(0.50) WITHIN GROUP (ORDER BY b.anxiety_score) AS p50,
          percentile_cont(0.75) WITHIN GROUP (ORDER BY b.anxiety_score) AS p75
        FROM boroughs b
        WHERE b.anxiety_score IS NOT NULL
          AND EXISTS (SELECT 1 FROM properties p WHERE p.borough_id = b.id)
      SQL

      nte: fetch.call(<<~SQL),
        SELECT
          percentile_cont(0.25) WITHIN GROUP (ORDER BY b.nte_score) AS p25,
          percentile_cont(0.50) WITHIN GROUP (ORDER BY b.nte_score) AS p50,
          percentile_cont(0.75) WITHIN GROUP (ORDER BY b.nte_score) AS p75
        FROM boroughs b
        WHERE b.nte_score IS NOT NULL
          AND EXISTS (SELECT 1 FROM properties p WHERE p.borough_id = b.id)
      SQL
    }.compact
  end

  # Builds threshold rules with all three percentiles so the model can choose
  # the right cut-point based on how strong the user's language is.
  # e.g. "a bit quiet" → P50, "very quiet" → P25, "extremely quiet" → P25
  def build_system_prompt(t)
    rules = []

    if (c = t[:crime])
      rules << <<~RULE.strip
        - Crime rate (max_crime_rate): P25=#{c[:p25]}, P50=#{c[:p50]}, P75=#{c[:p75]} crimes/month
            "safe" / "low crime" → P25 (#{c[:p25]}); "reasonably safe" → P50 (#{c[:p50]}); "avoid very high crime" → P75 (#{c[:p75]})
      RULE
    end

    if (d = t[:daqi])
      rules << <<~RULE.strip
        - Air quality index (max_daqi, 1=best 10=worst): P25=#{d[:p25]&.ceil}, P50=#{d[:p50]&.ceil}, P75=#{d[:p75]&.ceil}
            "excellent air quality" / "clean air" → P25 (#{d[:p25]&.ceil}); "good air" → P50 (#{d[:p50]&.ceil}); "acceptable air" → P75 (#{d[:p75]&.ceil})
      RULE
    end

    if (r = t[:road_noise])
      rules << <<~RULE.strip
        - Road noise lden (max_road_noise_lden, dB): P25=#{r[:p25]}, P50=#{r[:p50]}, P75=#{r[:p75]}
            "very quiet road" → P25 (#{r[:p25]}); "reasonably quiet" → P50 (#{r[:p50]}); "not too noisy" → P75 (#{r[:p75]})
      RULE
    end

    if (r = t[:rail_noise])
      rules << <<~RULE.strip
        - Rail noise lden (max_rail_noise_lden, dB): P25=#{r[:p25]}, P50=#{r[:p50]}, P75=#{r[:p75]}
            "very quiet rail" → P25 (#{r[:p25]}); "reasonably quiet" → P50 (#{r[:p50]}); "not too noisy" → P75 (#{r[:p75]})
      RULE
    end

    if (r = t[:flight_noise])
      rules << <<~RULE.strip
        - Flight noise lden (max_flight_noise_lden, dB): P25=#{r[:p25]}, P50=#{r[:p50]}, P75=#{r[:p75]}
            "minimal flight noise" → P25 (#{r[:p25]}); "some flight noise ok" → P50 (#{r[:p50]}); "not too much" → P75 (#{r[:p75]})
      RULE
    end

    if (ls = t[:life_satisfaction])
      rules << <<~RULE.strip
        - Borough life satisfaction (min_life_satisfaction, 0–1): P25=#{ls[:p25]}, P50=#{ls[:p50]}, P75=#{ls[:p75]}
            "very happy area" → P75 (#{ls[:p75]}); "happy area" → P50 (#{ls[:p50]}); "decent wellbeing" → P25 (#{ls[:p25]})
      RULE
    end

    if (h = t[:happiness])
      rules << <<~RULE.strip
        - Borough happiness (min_happiness, 0–1): P25=#{h[:p25]}, P50=#{h[:p50]}, P75=#{h[:p75]}
            "very happy" → P75 (#{h[:p75]}); "happy" → P50 (#{h[:p50]}); "decent" → P25 (#{h[:p25]})
      RULE
    end

    if (a = t[:anxiety])
      rules << <<~RULE.strip
        - Borough anxiety (max_anxiety, 0–1, lower=calmer): P25=#{a[:p25]}, P50=#{a[:p50]}, P75=#{a[:p75]}
            "very calm / low stress" → P25 (#{a[:p25]}); "fairly calm" → P50 (#{a[:p50]}); "not too stressful" → P75 (#{a[:p75]})
      RULE
    end

    if (n = t[:nte])
      rules << <<~RULE.strip
        - Night-time economy (min/max_nte_score, 0–1): P25=#{n[:p25]}, P50=#{n[:p50]}, P75=#{n[:p75]}
            "very vibrant / nightlife" → min_nte_score P75 (#{n[:p75]}); "some nightlife" → min_nte_score P50 (#{n[:p50]})
            "very quiet borough" → max_nte_score P25 (#{n[:p25]}); "fairly residential" → max_nte_score P50 (#{n[:p50]})
      RULE
    end

    format(
      PROMPT_TEMPLATE,
      rules:         rules.any? ? rules.map { |r| r.gsub(/^/, "    ") }.join("\n") : "    (no threshold data available yet — use your best judgement)",
      example_daqi:  t.dig(:daqi, :p50)&.ceil  || 4,
      example_crime: t.dig(:crime, :p25)&.round(1) || 20
    )
  end

  def apply_filters(scope, filters)
    # Property basics
    scope = scope.where(status: filters["status"])               if filters["status"].present?
    scope = scope.where(property_type: filters["property_type"]) if filters["property_type"].present?
    scope = scope.where(tenure: filters["tenure"])               if filters["tenure"].present?
    scope = scope.with_shared_ownership(filters["is_shared_ownership"]) if filters["is_shared_ownership"].present?

    # Price & size
    scope = scope.min_price(filters["min_price"].to_i)                   if filters["min_price"].present?
    scope = scope.max_price(filters["max_price"].to_i)                   if filters["max_price"].present?
    scope = scope.min_price_per_sqft(filters["min_price_per_sqft"].to_i) if filters["min_price_per_sqft"].present?
    scope = scope.max_price_per_sqft(filters["max_price_per_sqft"].to_i) if filters["max_price_per_sqft"].present?
    scope = scope.min_sqft(filters["min_sqft"].to_i)                     if filters["min_sqft"].present?
    scope = scope.min_beds(filters["min_beds"].to_i)                     if filters["min_beds"].present?
    scope = scope.max_beds(filters["max_beds"].to_i)                     if filters["max_beds"].present?
    scope = scope.min_bathrooms(filters["min_bathrooms"].to_i)           if filters["min_bathrooms"].present?
    scope = scope.epc_rating_min(filters["min_epc_rating"])              if filters["min_epc_rating"].present?

    # Environment & safety
    scope = scope.max_daqi(filters["max_daqi"].to_i)                          if filters["max_daqi"].present?
    scope = scope.max_flood_risk_band(filters["max_flood_risk_band"].to_i)    if filters["max_flood_risk_band"].present?
    scope = scope.max_crime_rate(filters["max_crime_rate"].to_f)              if filters["max_crime_rate"].present?
    scope = scope.max_road_noise_lden(filters["max_road_noise_lden"].to_f)    if filters["max_road_noise_lden"].present?
    scope = scope.max_rail_noise_lden(filters["max_rail_noise_lden"].to_f)    if filters["max_rail_noise_lden"].present?
    scope = scope.max_flight_noise_lden(filters["max_flight_noise_lden"].to_f) if filters["max_flight_noise_lden"].present?

    # Borough wellbeing
    scope = scope.min_life_satisfaction(filters["min_life_satisfaction"].to_f) if filters["min_life_satisfaction"].present?
    scope = scope.min_happiness(filters["min_happiness"].to_f)                 if filters["min_happiness"].present?
    scope = scope.max_anxiety(filters["max_anxiety"].to_f)                     if filters["max_anxiety"].present?
    scope = scope.min_nte_score(filters["min_nte_score"].to_f)                 if filters["min_nte_score"].present?
    scope = scope.max_nte_score(filters["max_nte_score"].to_f)                 if filters["max_nte_score"].present?

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
