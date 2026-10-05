# frozen_string_literal: true

module Trek
  class SyncSchedulingJob < ApplicationJob
    queue_as :imports

    def perform
      JobOwnership.with_owner('cron:trek_sync_job') do
        TripSource.active.where(provider: 'trek').find_each do |source|
          next unless source.sync_allowed?

          Trek::SyncJob.perform_later(source.id)
        end
      end
    end
  end
end
