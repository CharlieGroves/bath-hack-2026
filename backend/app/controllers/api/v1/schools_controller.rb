module Api
  module V1
    class SchoolsController < ApplicationController
      skip_before_action :verify_authenticity_token

      # GET /api/v1/schools/:id
      def show
        school = School.find(params[:id])
        render json: school_payload(school)
      rescue ActiveRecord::RecordNotFound
        render json: { error: "School not found" }, status: :not_found
      end

      private

      def school_payload(s)
        {
          id:        s.id,
          urn:       s.urn,
          name:      s.name,
          address1:  s.address1,
          address2:  s.address2,
          town:      s.town,
          postcode:  s.postcode,
          p8mea:     s.p8mea,
          latitude:  s.latitude,
          longitude: s.longitude
        }
      end
    end
  end
end
