module Api
  module V1
    class AirQualityStationsController < ApplicationController
      skip_before_action :verify_authenticity_token

      # GET /api/v1/air_quality_stations/:id
      def show
        station = AirQualityStation.find(params[:id])
        render json: station_payload(station)
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Station not found" }, status: :not_found
      end

      private

      def station_payload(station)
        {
          id:                  station.id,
          name:                station.name,
          latitude:            station.latitude,
          longitude:           station.longitude,
          daqi_index:          station.daqi_index,
          daqi_band:           station.daqi_band,
          readings_fetched_at: station.readings_fetched_at
        }
      end
    end
  end
end
