module Api
  module V1
    class ModelSearchesController < ApplicationController
      skip_before_action :verify_authenticity_token

      # POST /api/v1/model_searches
      # Body: { prompt: "2 bed flat under £400k with good air quality" }
      # Returns: { id, status } — frontend polls GET to check for completion
      def create
        search = ModelSearch.create!(prompt: params.require(:prompt))
        ModelSearchJob.perform_later(search.id)
        render json: { id: search.id, status: search.status }, status: :accepted
      rescue ActionController::ParameterMissing => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # GET /api/v1/model_searches/:id
      # Returns status + filters always; properties array when complete; error when failed
      def show
        search = ModelSearch.find(params[:id])
        render json: search_payload(search)
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Not found" }, status: :not_found
      end

      private

      def search_payload(search)
        payload = {
          id:      search.id,
          status:  search.status,
          prompt:  search.prompt,
          filters: search.filters
        }

        if search.complete?
          properties = Property
            .includes(:property_transport_snapshot, :property_crime_snapshot,
                      :air_quality_station, :flood_risk_datapoint, :property_nearest_stations)
            .where(id: search.result_ids)
            .index_by(&:id)

          payload[:properties] = search.result_ids.filter_map { |id| properties[id] }
                                        .map { |p| property_summary(p) }
        end

        payload[:error] = search.error_message if search.failed?
        payload
      end

      def property_summary(property)
        {
          id:               property.id,
          rightmove_id:     property.rightmove_id,
          title:            property.title,
          address:          property.address_line_1,
          price:            property.price_pence,
          price_per_sqft:   property.price_per_sqft_pence,
          bedrooms:         property.bedrooms,
          bathrooms:        property.bathrooms,
          property_type:    property.property_type,
          tenure:           property.tenure,
          status:           property.status,
          listed_at:        property.listed_at,
          latitude:         property.latitude,
          longitude:        property.longitude,
          photo_url:        property.photo_urls.first,
          air_quality:      air_quality_payload(property.air_quality_station),
          flood_risk:       flood_risk_payload(property.flood_risk_datapoint),
          noise:            noise_payload(property.property_transport_snapshot),
          crime:            crime_payload(property.property_crime_snapshot),
          nearest_stations: property.property_nearest_stations.sort_by(&:distance_miles).map { |s|
            { name: s.name, distance_miles: s.distance_miles, walking_minutes: s.walking_minutes,
              transport_type: s.transport_type, termini: s.termini }
          }
        }
      end

      def air_quality_payload(station)
        return nil unless station&.daqi_index
        { daqi_index: station.daqi_index, daqi_band: station.daqi_band, station_name: station.name }
      end

      def flood_risk_payload(datapoint)
        return nil unless datapoint
        { risk_level: datapoint.risk_level, risk_band: datapoint.risk_band }
      end

      def noise_payload(snapshot)
        return nil unless snapshot
        { provider: snapshot.provider, status: snapshot.status, fetched_at: snapshot.fetched_at,
          flight_data: snapshot.flight_data, rail_data: snapshot.rail_data, road_data: snapshot.road_data }
      end

      def crime_payload(snapshot)
        return nil unless snapshot
        { status: snapshot.status, avg_monthly_crimes: snapshot.avg_monthly_crimes, fetched_at: snapshot.fetched_at }
      end
    end
  end
end
