module Api
  module V1
    class PropertiesController < ApplicationController
      skip_before_action :verify_authenticity_token
      before_action :set_property, only: %i[show update destroy]

      # GET /api/v1/properties
      def index
        properties = Property.includes(:property_transport_snapshot, :property_crime_snapshot, :property_nearest_stations, :air_quality_station).order(created_at: :desc)
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
            latitude:  params[:sw_lat].to_f..params[:ne_lat].to_f,
            longitude: params[:sw_lng].to_f..params[:ne_lng].to_f
          )
        end

        total = properties.count
        render json: {
          properties: properties.limit(500).map { |p| property_summary(p) },
          total: total
        }
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
          .includes(:property_nearest_stations, :area_price_growth, :property_transport_snapshot, :air_quality_station)
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

      def property_summary(p)
        {
          id:            p.id,
          rightmove_id:  p.rightmove_id,
          title:         p.title,
          address:       p.address_line_1,
          price:              p.price_pence,
          price_per_sqft:     p.price_per_sqft_pence,
          bedrooms:      p.bedrooms,
          bathrooms:     p.bathrooms,
          property_type: p.property_type,
          status:        p.status,
          listed_at:     p.listed_at,
          latitude:      p.latitude,
          longitude:     p.longitude,
          photo_url:        p.photo_urls.first,
          noise:            noise_payload(p.property_transport_snapshot),
          crime:            crime_payload(p.property_crime_snapshot),
          air_quality:      air_quality_payload(p.air_quality_station),
          nearest_stations: p.property_nearest_stations.sort_by(&:distance_miles).map { |s|
            { name: s.name, distance_miles: s.distance_miles, walking_minutes: s.walking_minutes, transport_type: s.transport_type }
          }
        }
      end

      def property_detail(p)
        {
          id: p.id, rightmove_id: p.rightmove_id, slug: p.slug, listing_url: p.listing_url,
          title: p.title, description: p.description,
          address_line_1: p.address_line_1, town: p.town, postcode: p.postcode,
          price_pence: p.price_pence, price_qualifier: p.price_qualifier,
          price_per_sqft_pence: p.price_per_sqft_pence,
          property_type: p.property_type, bedrooms: p.bedrooms, bathrooms: p.bathrooms,
          size_sqft: p.size_sqft, tenure: p.tenure, lease_years_remaining: p.lease_years_remaining,
          epc_rating: p.epc_rating, council_tax_band: p.council_tax_band,
          service_charge_annual_pence: p.service_charge_annual_pence,
          photo_urls: p.photo_urls, key_features: p.key_features,
          latitude: p.latitude, longitude: p.longitude,
          agent_name: p.agent_name, agent_phone: p.agent_phone,
          status: p.status, listed_at: p.listed_at,
          noise: noise_payload(p.property_transport_snapshot),
          nearest_stations: p.property_nearest_stations
            .sort_by(&:distance_miles)
            .map { |s|
              { name: s.name, distance_miles: s.distance_miles,
                walking_minutes: s.walking_minutes, transport_type: s.transport_type }
            },
          area_price_growth: area_price_growth_payload(p.area_price_growth),
          air_quality:       air_quality_payload(p.air_quality_station),
        }
      end

      def area_price_growth_payload(apg)
        return nil unless apg
        { area_name: apg.area_name, area_slug: apg.area_slug,
          yearly_growth_data: apg.yearly_growth_data }
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
          status:             snapshot.status,
          avg_monthly_crimes: snapshot.avg_monthly_crimes,
          fetched_at:         snapshot.fetched_at
        }
      end

      def air_quality_payload(station)
        return nil unless station&.daqi_index
        { daqi_index: station.daqi_index, daqi_band: station.daqi_band, station_name: station.name }
      end
    end
  end
end
