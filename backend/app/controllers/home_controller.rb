class HomeController < ApplicationController
  def index
    @total_properties    = Property.count
    @by_status           = Property.group(:status).count
    @by_type             = Property.group(:property_type).count
    @avg_price_pence     = Property.average(:price_pence)&.round
    @recent_properties   = Property.order(created_at: :desc).limit(5)
  end
end
