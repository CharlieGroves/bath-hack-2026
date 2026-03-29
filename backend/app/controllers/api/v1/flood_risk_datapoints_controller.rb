module Api
  module V1
    class FloodRiskDatapointsController < ApplicationController
      skip_before_action :verify_authenticity_token

      # GET /api/v1/flood_risk_datapoints/:id
      def show
        datapoint = FloodRiskDatapoint.find(params[:id])
        render json: datapoint_payload(datapoint)
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Flood risk datapoint not found" }, status: :not_found
      end

      private

      def datapoint_payload(dp)
        {
          id:         dp.id,
          latitude:   dp.latitude,
          longitude:  dp.longitude,
          risk_level: dp.risk_level,
          risk_band:  dp.risk_band
        }
      end
    end
  end
end
