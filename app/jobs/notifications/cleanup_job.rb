# frozen_string_literal: true

module Notifications
  # Read notifications are history nobody returns to; unread ones are kept
  # until the user deals with them.
  class CleanupJob < ApplicationJob
    queue_as :low_priority

    RETENTION = 30.days

    # ponytail: one sequential scan of notifications a day; add a partial index
    # on read_at if it shows up in slow-query logs.
    # delete_all skips the broadcast callbacks on purpose: read notifications
    # are not in anyone's bell.
    def perform
      cutoff = RETENTION.ago
      deleted = Notification.where(read_at: ...cutoff).in_batches(of: 1_000).delete_all

      Rails.logger.info("Notifications::CleanupJob deleted #{deleted} notifications read before #{cutoff.to_date}")
    end
  end
end
