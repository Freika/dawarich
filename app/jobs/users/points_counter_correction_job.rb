# frozen_string_literal: true

class Users::PointsCounterCorrectionJob < ApplicationJob
  queue_as :low_priority

  OWNERSHIP_KEY = 'cron:points_counter_correction_job'
  BATCH_SIZE = 1000

  def perform
    User.active_or_trial.in_batches(of: BATCH_SIZE) do |batch|
      owned = JobOwnership.with_owner(OWNERSHIP_KEY) { batch.each { |user| correct(user) } }
      break if owned == :not_owner
    end
  end

  private

  def correct(user)
    actual_count = user.points.count
    return if user.points_count == actual_count

    user.update_column(:points_count, actual_count)
  end
end
