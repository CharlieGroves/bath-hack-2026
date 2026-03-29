module Api
  module V1
    class BoroughsController < ApplicationController
      skip_before_action :verify_authenticity_token

      # GET /api/v1/boroughs/:id
      def show
        borough = Borough.find(params[:id])
        render json: borough_payload(borough)
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Borough not found" }, status: :not_found
      end

      private

      def borough_payload(b)
        {
          id:                          b.id,
          name:                        b.name,
          nte_score:                   b.nte_score,
          nte_score_raw:               b.nte_score_raw,
          life_satisfaction_score:     b.life_satisfaction_score,
          life_satisfaction_score_raw: b.life_satisfaction_score_raw,
          happiness_score:             b.happiness_score,
          happiness_score_raw:         b.happiness_score_raw,
          anxiety_score:               b.anxiety_score,
          anxiety_score_raw:           b.anxiety_score_raw
        }
      end
    end
  end
end
