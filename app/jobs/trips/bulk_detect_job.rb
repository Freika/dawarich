# frozen_string_literal: true

# The daily Trip Detection run: one Trips::DetectJob for every active or trial
# user with a Home, spread over time in batches so the trips queue is not
# flooded at once.
class Trips::BulkDetectJob < ApplicationJob
  queue_as :trips

  BATCH_SIZE = 200
  STAGGER = 5.minutes

  def perform
    return unless Trips::DetectJob.instance_enabled?

    user_ids = User.active_or_trial.where(id: Home.select(:user_id)).order(:id).pluck(:id)
    jobs = user_ids.each_slice(BATCH_SIZE).with_index.flat_map do |batch, index|
      batch.map { |user_id| Trips::DetectJob.new(user_id).set(wait: index * STAGGER) }
    end

    ActiveJob.perform_all_later(jobs)
  end
end
