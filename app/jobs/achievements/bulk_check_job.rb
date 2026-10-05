# frozen_string_literal: true

module Achievements
  class BulkCheckJob < ApplicationJob
    queue_as :achievements

    BATCH_SIZE = 200
    STAGGER = 5.minutes

    # Spreads the fleet-wide check across time so a full run doesn't enqueue
    # every user's CheckJob at once (thundering herd on the achievements queue).
    # notify: false is used for backfills so historical earns don't blast alerts.
    def perform(cron_origin = nil, notify: true, force: false, stale_only: false)
      commands = Achievements::BulkCommands
      slot = Integrations::SchedulingCommands.slot(self, cron_origin) if cron_origin
      return if cron_origin && JobOwnership.with_owner(commands::KEY) { :owned } == :not_owner

      options = { notify: notify, force: force, stale_only: stale_only }
      event = commands.root(job_id, slot)
      return if commands.forward(options, event)

      user_ids = eligible_user_ids
      user_ids -= current_user_ids if stale_only

      user_ids.each_slice(BATCH_SIZE).with_index do |batch, index|
        work = lambda {
          batch.each do |user_id|
            next if slot && !commands.claim(event, user_id)

            commands.schedule(user_id, options, Time.current + index * STAGGER, event)
          end
        }
        if cron_origin
          break if JobOwnership.with_owner(commands::KEY, &work) == :not_owner
        else
          ActiveRecord::Base.transaction { work.call }
        end
      end
    end

    private

    def eligible_user_ids
      statuses = User.statuses.values_at('active', 'trial')

      User.where(status: statuses)
          .where(id: Point.not_anomaly.where.not(lonlat: nil).select(:user_id))
          .order(:id)
          .pluck(:id)
    end

    def current_user_ids
      Progress.current_exploration.pluck(:user_id)
    end
  end
end
