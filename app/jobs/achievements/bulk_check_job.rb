# frozen_string_literal: true

module Achievements
  class BulkCheckJob < ApplicationJob
    queue_as :achievements

    BATCH_SIZE = 200
    STAGGER = 5.minutes

    # Spreads the fleet-wide check across time so a full run doesn't enqueue
    # every user's CheckJob at once (thundering herd on the achievements queue).
    # notify: false is used for backfills so historical earns don't blast alerts.
    def perform(notify: true, force: false)
      return unless force || Flipper.enabled?(:achievements)

      user_ids = (User.active.pluck(:id) + User.trial.pluck(:id)).uniq

      user_ids.each_slice(BATCH_SIZE).with_index do |batch, index|
        batch.each do |user_id|
          Achievements::CheckJob.set(wait: index * STAGGER).perform_later(user_id, notify: notify, force: force)
        end
      end
    end
  end
end
