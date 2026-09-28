# frozen_string_literal: true

module Notifications
  module EventsBroadcaster
    POLL_SECONDS = 1
    BATCH = 100
    THREAD_NAME = 'notification-events'
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
      Rails.logger.warn("[Notifications] events: #{e.class}")
      sleep(5)
    end

    def drain_once
      Rails.application.executor.wrap do
        ids = claim
        Notification.where(id: ids).includes(:user).order(:id).each(&:broadcast_notification)
        ids.size
      end
    end

    def claim
      connection = ActiveRecord::Base.connection
      return [] unless connection.select_value("SELECT to_regclass('phoenix.notification_events') IS NOT NULL")

      connection.select_values(<<~SQL.squish)
        DELETE FROM phoenix.notification_events WHERE id IN (
          SELECT id FROM phoenix.notification_events ORDER BY id LIMIT #{BATCH} FOR UPDATE SKIP LOCKED)
        RETURNING notification_id
      SQL
    end

    def spawn
      thread = Thread.new { loop { drain_safely } }
      thread.name = THREAD_NAME
      thread
    end
    private_class_method :spawn
  end
end
