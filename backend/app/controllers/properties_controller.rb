class PropertiesController < ApplicationController
  before_action :set_property, only: %i[show edit update destroy]

  def index
    @properties = Property.all.order(created_at: :desc)
    @properties = @properties.where(status: params[:status])               if params[:status].present?
    @properties = @properties.where(property_type: params[:property_type]) if params[:property_type].present?
    @properties = @properties.min_price(params[:min_price].to_i)           if params[:min_price].present?
    @properties = @properties.max_price(params[:max_price].to_i)           if params[:max_price].present?
    @properties = @properties.min_beds(params[:min_beds].to_i)             if params[:min_beds].present?
    @properties = @properties.with_shared_ownership(params[:is_shared_ownership]) if params[:is_shared_ownership].present?
    @properties = @properties.page(params[:page]).per(25)
  end

  def show; end

  def new
    @property = Property.new
  end

  def edit; end

  def create
    @property = Property.new(property_params)
    if @property.save
      redirect_to @property, notice: "Property created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @property.update(property_params)
      redirect_to @property, notice: "Property updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @property.destroy
    redirect_to properties_path, notice: "Property deleted."
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
      :status, :listed_at
    )
  end
end
