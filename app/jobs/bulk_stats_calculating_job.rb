# frozen_string_literal: true

class BulkStatsCalculatingJob < ApplicationJob
  queue_as :stats
  OWNER_KEY = 'cron:bulk_stats_calculating_job'

  def perform
    return if JobOwnership.oban?(OWNER_KEY)

    user_ids = User.active.pluck(:id) + User.trial.pluck(:id)
    return if user_ids.empty?

    failed = user_ids.count { |user_id| !calculate_for(user_id) }

    return unless failed == user_ids.size

    raise Stats::SweepFailed, "stats calculation failed for all #{failed} users"
  end

  private

  def calculate_for(user_id)
    Stats::BulkCalculator.new(user_id).call

    true
  rescue StandardError => e
    message = "BulkStatsCalculatingJob failed for user #{user_id}"

    Rails.logger.error("#{message}: #{e.class}: #{e.message}")
    ExceptionReporter.call(e, message)

    false
  end
end
