# frozen_string_literal: true

module Achievements
  class BulkCheckJob < ApplicationJob
    queue_as :achievements

    BATCH_SIZE = 200
    STAGGER = 5.minutes

    # Spreads the fleet-wide check across time so a full run doesn't enqueue
    # every user's CheckJob at once (thundering herd on the achievements queue).
    # notify: false is used for backfills so historical earns don't blast alerts.
    def perform(notify: true, force: false, stale_only: false)
      return unless force || Flipper.enabled?(:achievements)

      user_ids = eligible_user_ids
      user_ids -= current_user_ids if stale_only

      user_ids.each_slice(BATCH_SIZE).with_index do |batch, index|
        batch.each do |user_id|
          Achievements::CheckJob.set(wait: index * STAGGER).perform_later(user_id, notify: notify, force: force)
        end
      end
    end

    private

    def eligible_user_ids
      statuses = User.statuses.values_at('active', 'trial')

      User.where(status: statuses)
          .where(id: Point.not_anomaly.where.not(lonlat: nil).select(:user_id))
          .pluck(:id)
    end

    def current_user_ids
      Progress.current_exploration.pluck(:user_id)
    end
  end
end
