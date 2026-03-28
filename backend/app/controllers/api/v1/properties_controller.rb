module Api
  module V1
    class PropertiesController < ApplicationController
      skip_before_action :verify_authenticity_token
      before_action :set_property, only: %i[show update destroy]

      # GET /api/v1/properties
      def index
        properties = Property.includes(:property_transport_snapshot).order(created_at: :desc)
        properties = properties.where(status: params[:status])               if params[:status].present?
        properties = properties.where(property_type: params[:property_type]) if params[:property_type].present?
        properties = properties.min_price(params[:min_price].to_i)           if params[:min_price].present?
        properties = properties.max_price(params[:max_price].to_i)           if params[:max_price].present?
        properties = properties.min_beds(params[:min_beds].to_i)             if params[:min_beds].present?
        properties = properties.max_beds(params[:max_beds].to_i)             if params[:max_beds].present?

        render json: {
          properties: properties.map { |p| property_summary(p) },
          total: properties.count
        }
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
        @property = Property.friendly.find(params[:id])
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
          price:         p.price_pence,
          bedrooms:      p.bedrooms,
          bathrooms:     p.bathrooms,
          property_type: p.property_type,
          status:        p.status,
          listed_at:     p.listed_at,
          latitude:      p.latitude,
          longitude:     p.longitude,
          photo_url:     p.photo_urls.first,
          noise:         noise_payload(p.property_transport_snapshot)
        }
      end

      def property_detail(p)
        p.as_json(except: :raw_data).merge(
          noise: noise_payload(p.property_transport_snapshot)
        )
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
    end
  end
end
