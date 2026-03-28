require "json"

class GeoapifyAutocompleteGateway
  BASE_URL = "https://api.geoapify.com".freeze
  MIN_QUERY_LENGTH = 3
  DEFAULT_LIMIT = 6

  class Error < StandardError; end
  class RequestError < Error; end

  def initialize(connection: Faraday.new(url: BASE_URL), api_key: ENV["GEOAPIFY_API_KEY"])
    @connection = connection
    @api_key = api_key
  end

  def configured?
    @api_key.present?
  end

  def autocomplete(query:, limit: DEFAULT_LIMIT)
    return [] unless configured?

    response = @connection.get("/v1/geocode/autocomplete") do |request|
      request.headers["Accept"] = "application/json"
      request.params["text"] = query.to_s.strip
      request.params["format"] = "json"
      request.params["lang"] = "en"
      request.params["limit"] = limit.to_i
      request.params["apiKey"] = @api_key
    end

    raise RequestError, "Location autocomplete failed with status #{response.status}" unless response.success?

    payload = JSON.parse(response.body.to_s)
    Array(payload["results"]).filter_map.with_index do |result, index|
      normalize_result(result, index)
    end
  rescue Faraday::Error => e
    raise RequestError, "Location autocomplete failed: #{e.message}"
  rescue JSON::ParserError => e
    raise RequestError, "Location autocomplete returned invalid JSON: #{e.message}"
  end

  private

  def normalize_result(result, index)
    label = result["formatted"].to_s.strip.presence || result["address_line1"].to_s.strip.presence
    return nil unless label

    secondary_label = result["address_line2"].to_s.strip.presence

    {
      id: result["place_id"].presence || "#{label.parameterize}-#{index}",
      label: label,
      secondary_label: secondary_label == label ? nil : secondary_label,
      latitude: numeric_or_nil(result["lat"]),
      longitude: numeric_or_nil(result["lon"]),
      result_type: result["result_type"].to_s.strip.presence
    }
  end

  def numeric_or_nil(value)
    return nil if value.blank?

    value.to_f
  end
end
