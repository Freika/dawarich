# frozen_string_literal: true

module Api
  module V1
    class TimelineController < ApiController
      def index
        unit = params[:distance_unit].presence || current_api_user.safe_settings.distance_unit

        days = Timeline::DayAssembler.new(
          current_api_user,
          start_at: params[:start_at],
          end_at: params[:end_at],
          distance_unit: unit
        ).call

        render json: { days: days }
      end
    end
  end
end
