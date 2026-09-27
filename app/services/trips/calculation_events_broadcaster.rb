# frozen_string_literal: true

module Trips
  module CalculationEventsBroadcaster
    POLL_SECONDS = 1
    BATCH = 100
    THREAD_NAME = 'trip-calculation-events'
    THREAD_LOCK = Mutex.new

    module_function

    def start
      return if Rails.env.test?

      THREAD_LOCK.synchronize do
        Thread.list.find { |thread| thread.name == THREAD_NAME } || spawn
      end
    end

    def stop
      thread = Thread.list.find { |candidate| candidate.name == THREAD_NAME }
      thread&.kill
      thread&.join
    end

    def drain_safely
      sleep(POLL_SECONDS) if drain_once.zero?
    rescue ActiveRecord::ActiveRecordError, PG::Error => e
      Rails.logger.warn("[Trips] calculation events: #{e.class}")
      sleep(5)
    end

    def drain_once
      Rails.application.executor.wrap do
        events = claim
        events.each { |event| broadcast(event) }
        events.size
      end
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

    def spawn
      thread = Thread.new { loop { drain_safely } }
      thread.name = THREAD_NAME
      thread
    end
    private_class_method :spawn
  end
end
