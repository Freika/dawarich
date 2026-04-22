# frozen_string_literal: true

module GeofenceEvents
  module Evaluator
    class ForPoint
      MAX_ACCURACY_M = 500

      def self.call(user, point)
        new(user, point).call
      end

      def initialize(user, point)
        @user = user
        @point = point
      end

      def call
        return if skip_for_accuracy?

        inside_now = areas_containing_point.pluck(:id).to_set
        inside_before = StateStore.currently_inside(@user)

        (inside_now - inside_before).each { |area_id| emit(area_id, :enter) }
        (inside_before - inside_now).each { |area_id| emit(area_id, :leave) }
      rescue Redis::BaseError => e
        Sentry.capture_exception(e, extra: { user_id: @user.id })
        nil
      end

      private

      def skip_for_accuracy?
        (@point.accuracy || 0) > MAX_ACCURACY_M
      end

      def areas_containing_point
        @user.areas.where(
          'ST_DWithin(
             ST_SetSRID(ST_MakePoint(areas.longitude, areas.latitude), 4326)::geography,
             ?::geography,
             areas.radius + ?
           )',
          @point.lonlat,
          @point.accuracy.to_i
        )
      end

      def emit(area_id, event_type)
        area = Area.find(area_id)
        Record.call(
          user: @user,
          area: area,
          event_type: event_type,
          source: :server_inferred,
          occurred_at: Time.zone.at(@point.timestamp.to_i),
          lonlat: @point.lonlat,
          accuracy_m: @point.accuracy
        )
      end
    end
  end
end
