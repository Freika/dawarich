# frozen_string_literal: true

class BulkStatsCalculatingJob < ApplicationJob
  queue_as :stats
  OWNER_KEY = 'cron:bulk_stats_calculating_job'

  def perform
    return if JobOwnership.oban?(OWNER_KEY)

    user_ids = User.active.pluck(:id) + User.trial.pluck(:id)
    return if user_ids.empty?

    failed = 0
    processed = 0
    user_ids.each do |user_id|
      result = JobOwnership.with_owner(OWNER_KEY) { calculate_for(user_id) }
      break if result == :not_owner

      processed += 1
      failed += 1 unless result
    end

    return unless processed.positive? && failed == processed

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
