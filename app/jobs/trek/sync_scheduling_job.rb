# frozen_string_literal: true

module Trek
  class SyncSchedulingJob < ApplicationJob
    queue_as :imports

    def perform
      TripSource.active.where(provider: 'trek').find_each do |source|
        Trek::SyncJob.perform_later(source.id)
      end
    end
  end
end
