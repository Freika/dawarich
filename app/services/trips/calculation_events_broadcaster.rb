# frozen_string_literal: true

module Trips
  module CalculationEventsBroadcaster
    extend PhoenixEventsPoller

    BATCH = 100
    THREAD_NAME = 'trip-calculation-events'
    LOG_TAG = '[Trips] calculation events'

    module_function

    def drain_once
      events = claim
      events.each { |event| broadcast(event) }
      events.size
    end

    def claim
      connection = ActiveRecord::Base.connection
      return [] unless connection.select_value("SELECT to_regclass('phoenix.trip_events') IS NOT NULL")

      connection.exec_query(<<~SQL.squish).to_a.sort_by { _1['id'] }
        DELETE FROM phoenix.trip_events WHERE id IN (
          SELECT id FROM phoenix.trip_events ORDER BY id LIMIT #{BATCH} FOR UPDATE SKIP LOCKED)
        RETURNING id, trip_id, kind, distance_unit, failed
      SQL
    end

    def broadcast(event)
      trip = Trip.find_by(id: event['trip_id'])
      return unless trip

      case event['kind']
      when 'path'
        Turbo::StreamsChannel.broadcast_refresh_to(trip)
      when 'distance', 'countries'
        Turbo::StreamsChannel.broadcast_update_to(trip, target: "trip_#{event['kind']}",
                                                        partial: "trips/#{event['kind']}",
                                                        locals: { trip:, distance_unit: event['distance_unit'] })
      when 'finished'
        Turbo::StreamsChannel.broadcast_replace_to(trip, target: 'trip_recalculate_frame',
                                                         partial: 'trips/recalculate_button',
                                                         locals: { trip:, error: event['failed'] })
      end
    end
  end
end
