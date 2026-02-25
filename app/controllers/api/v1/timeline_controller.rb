# frozen_string_literal: true

module Api
  module V1
    class TimelineController < ApiController
      MAX_RANGE_DAYS = 31

      def index
        unless date_params_present?
          return render json: { error: 'start_at and end_at are required' }, status: :bad_request
        end

        if range_too_large?
          return render json: { error: "Date range cannot exceed #{MAX_RANGE_DAYS} days" },
                        status: :bad_request
        end

        unit = params[:distance_unit].presence || current_api_user.safe_settings.distance_unit

        days = Timeline::DayAssembler.new(
          current_api_user,
          start_at: params[:start_at],
          end_at: params[:end_at],
          distance_unit: unit
        ).call

        render json: { days: days }
      end

      private

      def date_params_present?
        params[:start_at].present? && params[:end_at].present?
      end

      def range_too_large?
        start_at = Time.zone.parse(params[:start_at])
        end_at = Time.zone.parse(params[:end_at])
        return false unless start_at && end_at

        (end_at - start_at) > MAX_RANGE_DAYS.days
      end
    end
  end
end
