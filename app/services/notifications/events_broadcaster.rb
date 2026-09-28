# frozen_string_literal: true

module Notifications
  module EventsBroadcaster
    extend PhoenixEventsPoller

    BATCH = 100
    THREAD_NAME = 'notification-events'
    LOG_TAG = '[Notifications] events'

    module_function

    def drain_once
      ids = claim
      Notification.where(id: ids).includes(:user).order(:id).each(&:broadcast_notification)
      ids.size
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
  end
end
