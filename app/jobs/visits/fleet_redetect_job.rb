# frozen_string_literal: true

# Staged fleet rollout of detection v3: one per-user job per active user with
# points, all on low_priority so ordinary work is never starved. Cloud: Eugene
# starts this from the console. Self-hosted: enqueued by the release migration.
class Visits::FleetRedetectJob < ApplicationJob
  queue_as :low_priority
  sidekiq_options retry: 3

  BATCH_SIZE = 500

  def perform
    User.active.where(points_count: 1..).in_batches(of: BATCH_SIZE) do |batch|
      ActiveJob.perform_all_later(batch.ids.map { |id| Visits::UserRedetectJob.new(id) })
    end
  end
end
