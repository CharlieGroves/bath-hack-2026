module Api
  module V1
    class LocationAutocompleteController < ApplicationController
      skip_before_action :verify_authenticity_token

      def index
        gateway = GeoapifyAutocompleteGateway.new

        if params[:query].to_s.strip.length < GeoapifyAutocompleteGateway::MIN_QUERY_LENGTH
          render json: { suggestions: [], enabled: gateway.configured? }
          return
        end

        unless gateway.configured?
          render json: { suggestions: [], enabled: false, error: "Location autocomplete is not configured" },
                 status: :service_unavailable
          return
        end

        render json: {
          suggestions: gateway.autocomplete(query: params[:query]),
          enabled: true
        }
      rescue GeoapifyAutocompleteGateway::RequestError => e
        render json: { suggestions: [], enabled: true, error: e.message }, status: :bad_gateway
      end
    end
  end
end
