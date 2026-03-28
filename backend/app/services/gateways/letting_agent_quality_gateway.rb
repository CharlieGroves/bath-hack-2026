require "httparty"
require "json"

module Gateways
  class LettingAgentQualityGateway
    GOOGLE_PLACE_DETAILS_URL = "https://maps.googleapis.com/maps/api/place/details/json".freeze
    GOOGLE_FIND_PLACE_URL    = "https://maps.googleapis.com/maps/api/place/findplacefromtext/json".freeze

    class Error < StandardError; end

    def fetch_letting_agent_rating(name)
      place_id = find_place_id(name)
      return nil unless place_id

      data = fetch_place_details(place_id)
      return nil unless data

      {
        name: data[:name],
        rating: data[:rating]
      }
    end

    private

    def google_api_key
      key = ENV["GOOGLE_API_KEY"]&.strip
      raise Error, "Missing GOOGLE_API_KEY. Set it in backend/.env (see .env.example)" if key.blank?

      key
    end

    def find_place_id(name)
      query = name.to_s.strip
      return nil if query.blank?

      # Find Place only supports a small field mask; invalid combinations return INVALID_REQUEST.
      # Request place_id only, then load name/rating via Place Details.
      response = HTTParty.get(
        GOOGLE_FIND_PLACE_URL,
        query: {
          input: query,
          inputtype: "textquery",
          fields: "place_id",
          key: google_api_key
        },
        format: :plain
      )

      body = parse_google_json(response)
      status = body["status"]
      if status.present? && status != "OK" && status != "ZERO_RESULTS"
        msg = [status, body["error_message"]].compact.join(" — ")
        raise Error, "Google Places find: #{msg}"
      end

      candidates = body["candidates"]
      candidates&.first&.fetch("place_id", nil)
    end

    def fetch_place_details(place_id)
      response = HTTParty.get(
        GOOGLE_PLACE_DETAILS_URL,
        query: {
          place_id: place_id,
          fields: "name,rating",
          key: google_api_key
        },
        format: :plain
      )

      body = parse_google_json(response)
      status = body["status"]
      if status.present? && status != "OK"
        msg = [status, body["error_message"]].compact.join(" — ")
        raise Error, "Google Places details: #{msg}"
      end

      result = body["result"]
      return nil unless result

      {
        name: result["name"],
        rating: result["rating"].to_f
      }
    end

    def parse_google_json(response)
      raw = response.body.to_s
      JSON.parse(raw)
    rescue JSON::ParserError
      snippet = raw.bytesize > 200 ? "#{raw.byteslice(0, 200)}..." : raw
      raise Error, "Google Places: bad response (#{response.code}): #{snippet}"
    end
  end
end
