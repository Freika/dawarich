# frozen_string_literal: true

module Stats
  class ToponymsRefreshJob < ApplicationJob
    queue_as :stats
    OWNER_KEY = 'cron:stats_toponyms_refresh_job'

    def perform
      GeocodedDays.drain_redis
      return if JobOwnership.oban?(OWNER_KEY)

      ToponymsRefresh.new.call(owner_key: OWNER_KEY)
    end
  end
end
