# frozen_string_literal: true

# Staged fleet rollout of detection v3: one per-user job per active user with
# points, all on low_priority so ordinary work is never starved, staggered so
# the whole fleet doesn't land on the queue at once. Cloud: Eugene starts this
# from the console. Self-hosted: enqueued by the release migration.
class Visits::FleetRedetectJob < ApplicationJob
  queue_as :low_priority
  sidekiq_options retry: 3

  BATCH_SIZE = 500
  STAGGER_SECONDS = 30

  def perform
    offset = 0
    now = Time.current
    User.active.where(points_count: 1..).in_batches(of: BATCH_SIZE) do |batch|
      jobs = batch.ids.map do |id|
        job = Visits::UserRedetectJob.new(id)
        job.scheduled_at = now + offset
        offset += STAGGER_SECONDS
        job
      end
      ActiveJob.perform_all_later(jobs)
    end
  end
end
