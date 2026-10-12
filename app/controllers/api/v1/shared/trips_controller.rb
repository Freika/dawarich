# frozen_string_literal: true

module Api
  module V1
    module Shared
      class TripsController < BaseController
        def show
          trip = link.resource
          return render(json: { error: 'gone' }, status: :gone) if trip.nil?

          render json: serialize(trip)
        end

        private

        def serialize(trip)
          payload = {
            name:       trip.name,
            started_at: trip.started_at,
            ended_at:   trip.ended_at
          }
          if ctx.show_stats? && trip.distance.present?
            unit = link.user.safe_settings.distance_unit
            payload[:distance] = trip.distance_in_unit(unit).round
            payload[:distance_unit] = unit
          end
          payload
        end
      end
    end
  end
end
