module Api
  module V1
    class PropertiesController < ApplicationController
      skip_before_action :verify_authenticity_token
      before_action :set_property, only: %i[show update destroy]

      # GET /api/v1/properties
      def index
        render json: collection_payload(filtered_properties, limit: 500)
      end

      # GET /api/v1/properties/search
      def search
        result = PropertyLocationSearch.new(scope: filtered_properties).call(
          query: params[:query],
          transportation_type: params[:transportation_type],
          travel_time: travel_time_seconds
        )

        render json: collection_payload(result.fetch(:properties)).merge(
          query: result.fetch(:query),
          location: result.fetch(:location),
          transportation_type: result.fetch(:transportation_type),
          travel_time_seconds: result.fetch(:travel_time_seconds),
          bounding_box: result.fetch(:bounding_box),
          isochrone_shells: result.fetch(:isochrone_shells)
        )
      rescue PropertyLocationSearch::InvalidQuery,
             PropertyLocationSearch::InvalidTransportationType,
             PropertyLocationSearch::InvalidTravelTime => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue NominatimGeocoder::LocationNotFound => e
        render json: { error: e.message }, status: :not_found
      rescue NominatimGeocoder::RequestError,
             TravelTimeGateway::RequestError => e
        render json: { error: e.message }, status: :bad_gateway
      rescue TravelTimeGateway::ConfigError => e
        render json: { error: e.message }, status: :service_unavailable
      end

      # GET /api/v1/properties/heatmap
      def heatmap
        points = Property
          .where.not(latitude: nil, longitude: nil, price_per_sqft_pence: nil)
          .pluck(:latitude, :longitude, :price_per_sqft_pence)
        render json: { points: points }
      end

      # GET /api/v1/properties/:id
      def show
        render json: property_detail(@property)
      end

      # POST /api/v1/properties
      def create
        property = Property.create!(property_params)
        render json: property_detail(property), status: :created
      end

      # PATCH /PUT /api/v1/properties/:id
      def update
        @property.update!(property_params)
        render json: property_detail(@property)
      end

      # DELETE /api/v1/properties/:id
      def destroy
        @property.destroy!
        head :no_content
      end

      private

      def set_property
        @property = Property
          .includes(:property_nearest_stations, :area_price_growth, :property_transport_snapshot, :air_quality_station, :estate_agent)
          .friendly.find(params[:id])
      end

      def property_params
        params.require(:property).permit(
          :rightmove_id, :listing_url, :title, :description,
          :price_pence, :price_qualifier, :price_per_sqft_pence,
          :property_type, :bedrooms, :bathrooms, :size_sqft,
          :tenure, :lease_years_remaining,
          :epc_rating, :council_tax_band, :service_charge_annual_pence,
          :address_line_1, :town, :postcode, :latitude, :longitude,
          :agent_name, :agent_phone,
          :has_floor_plan, :has_virtual_tour,
          :utilities_text, :parking_text,
          :status, :listed_at,
          key_features: [], photo_urls: []
        )
      end

      def base_properties
        Property.includes(:property_transport_snapshot, :property_crime_snapshot, :property_nearest_stations, :air_quality_station, :estate_agent)
          .order(created_at: :desc)
      end

      def filtered_properties
        properties = base_properties
        properties = properties.where(status: params[:status])               if params[:status].present?
        properties = properties.where(property_type: params[:property_type]) if params[:property_type].present?
        properties = properties.min_price(params[:min_price].to_i)           if params[:min_price].present?
        properties = properties.max_price(params[:max_price].to_i)           if params[:max_price].present?
        properties = properties.min_beds(params[:min_beds].to_i)             if params[:min_beds].present?
        properties = properties.max_beds(params[:max_beds].to_i)             if params[:max_beds].present?
        properties = properties.max_daqi(params[:max_daqi].to_i)             if params[:max_daqi].present?

        if params[:sw_lat].present? && params[:sw_lng].present? &&
           params[:ne_lat].present? && params[:ne_lng].present?
          properties = properties.where(
            latitude: params[:sw_lat].to_f..params[:ne_lat].to_f,
            longitude: params[:sw_lng].to_f..params[:ne_lng].to_f
          )
        end

        properties
      end

      def collection_payload(properties, limit: nil)
        {
          properties: limited_collection(properties, limit).map { |property| property_summary(property) },
          total: properties.count
        }
      end

      def limited_collection(properties, limit)
        return properties unless limit
        return properties.limit(limit) if properties.respond_to?(:limit)

        Array(properties).first(limit)
      end

      def travel_time_seconds
        return PropertyLocationSearch::DEFAULT_TRAVEL_TIME if params[:travel_time_minutes].blank?

        params[:travel_time_minutes].to_i * 60
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
          status:           property.status,
          listed_at:        property.listed_at,
          latitude:         property.latitude,
          longitude:        property.longitude,
          photo_url:        property.photo_urls.first,
          noise:            noise_payload(property.property_transport_snapshot),
          crime:            crime_payload(property.property_crime_snapshot),
          air_quality:      air_quality_payload(property.air_quality_station),
          nearest_stations: property.property_nearest_stations.sort_by(&:distance_miles).map { |station|
            {
              name: station.name,
              distance_miles: station.distance_miles,
              walking_minutes: station.walking_minutes,
              transport_type: station.transport_type
            }
          }
        }
      end

      def property_detail(property)
        {
          id: property.id, rightmove_id: property.rightmove_id, slug: property.slug, listing_url: property.listing_url,
          title: property.title, description: property.description,
          address_line_1: property.address_line_1, town: property.town, postcode: property.postcode,
          price_pence: property.price_pence, price_qualifier: property.price_qualifier,
          price_per_sqft_pence: property.price_per_sqft_pence,
          property_type: property.property_type, bedrooms: property.bedrooms, bathrooms: property.bathrooms,
          size_sqft: property.size_sqft, tenure: property.tenure, lease_years_remaining: property.lease_years_remaining,
          epc_rating: property.epc_rating, council_tax_band: property.council_tax_band,
          service_charge_annual_pence: property.service_charge_annual_pence,
          photo_urls: property.photo_urls, key_features: property.key_features,
          latitude: property.latitude, longitude: property.longitude,
          agent_name: property.agent_name, agent_phone: property.agent_phone,
          estate_agent: estate_agent_payload(property.estate_agent),
          status: property.status, listed_at: property.listed_at,
          noise: noise_payload(property.property_transport_snapshot),
          nearest_stations: property.property_nearest_stations
            .sort_by(&:distance_miles)
            .map { |station|
              {
                name: station.name,
                distance_miles: station.distance_miles,
                walking_minutes: station.walking_minutes,
                transport_type: station.transport_type
              }
            },
          area_price_growth: area_price_growth_payload(property.area_price_growth),
          air_quality:       air_quality_payload(property.air_quality_station)
        }
      end

      def estate_agent_payload(estate_agent)
        return nil unless estate_agent

        {
          display_name: estate_agent.display_name,
          rating: estate_agent.rating&.to_f,
          google_place_id: estate_agent.google_place_id
        }
      end

      def area_price_growth_payload(area_price_growth)
        return nil unless area_price_growth

        {
          area_name: area_price_growth.area_name,
          area_slug: area_price_growth.area_slug,
          yearly_growth_data: area_price_growth.yearly_growth_data
        }
      end

      def noise_payload(snapshot)
        return nil unless snapshot

        {
          provider: snapshot.provider,
          status: snapshot.status,
          fetched_at: snapshot.fetched_at,
          flight_data: snapshot.flight_data,
          rail_data: snapshot.rail_data,
          road_data: snapshot.road_data
        }
      end

      def crime_payload(snapshot)
        return nil unless snapshot

        {
          status: snapshot.status,
          avg_monthly_crimes: snapshot.avg_monthly_crimes,
          fetched_at: snapshot.fetched_at
        }
      end

      def air_quality_payload(station)
        return nil unless station&.daqi_index
        { daqi_index: station.daqi_index, daqi_band: station.daqi_band, station_name: station.name }
      end
    end
  end
end
