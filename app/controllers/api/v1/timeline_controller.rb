# frozen_string_literal: true

module Api
  module V1
    class TimelineController < ApiController
      def index
        days = Timeline::DayAssembler.new(
          current_api_user,
          start_at: params[:start_at],
          end_at: params[:end_at]
        ).call

        render json: { days: days }
      end
    end
  end
end
