# frozen_string_literal: true

module Trek
  class SyncSchedulingJob < ApplicationJob
    queue_as :imports

    def perform
      sources = TripSource.active.where(provider: 'trek').find_each.select(&:sync_allowed?)
      ActiveJob.perform_all_later(sources.map { |source| Trek::SyncJob.new(source.id) })
    end
  end
end
