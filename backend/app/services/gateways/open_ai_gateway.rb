require "openai"

# Thin wrapper around the OpenAI Chat Completions API.
#
# Usage:
#   gateway = OpenAiGateway.new
#   response = gateway.chat(
#     system: "You are a helpful assistant.",
#     user:   "Find me a 2-bed flat under £500k"
#   )
#   # => String (assistant message content)
#
# Raises OpenAiGateway::Error on configuration or API errors.
class OpenAiGateway
  class Error < StandardError; end
  class ConfigError < Error; end

  MODEL   = "gpt-4o-mini".freeze
  TIMEOUT = 30

  def initialize(client: nil)
    @client = client || build_client
  end

  # Sends a single-turn chat and returns the assistant's reply as a String.
  #
  # @param system  [String]  system prompt
  # @param user    [String]  user message
  # @param format  [Symbol]  :text (default) or :json
  def chat(system:, user:, format: :text)
    params = {
      model:    MODEL,
      messages: [
        { role: "system", content: system },
        { role: "user",   content: user   }
      ]
    }
    params[:response_format] = { type: "json_object" } if format == :json

    response = @client.chat(parameters: params)
    content  = response.dig("choices", 0, "message", "content")

    raise Error, "Empty response from OpenAI" if content.blank?

    content
  rescue OpenAI::Error => e
    raise Error, "OpenAI API error: #{e.message}"
  rescue Faraday::Error => e
    raise Error, "Network error calling OpenAI: #{e.message}"
  end

  private

  def build_client
    api_key = ENV["OPENAI_API_KEY"]
    raise ConfigError, "OPENAI_API_KEY is not set" if api_key.blank?

    OpenAI::Client.new(
      access_token:  api_key,
      request_timeout: TIMEOUT
    )
  end
end
