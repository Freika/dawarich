# frozen_string_literal: true

class DeduplicateTracksAndAddUniqueIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  USER_DELAY_SECONDS = 30
  INITIAL_DELAY_MINUTES = 2

  def up
    enqueue_deduplication_jobs
  end

  def down
    # Jobs may have already run; nothing to reverse
  end

  private

  def enqueue_deduplication_jobs
    user_ids = User.pluck(:id)
    return if user_ids.empty?

    Rails.logger.info "[Migration] Enqueuing Tracks::DeduplicationJob for #{user_ids.size} users"

    user_ids.each_with_index do |user_id, index|
      delay = INITIAL_DELAY_MINUTES.minutes + (index * USER_DELAY_SECONDS).seconds
      Tracks::DeduplicationJob.set(wait: delay).perform_later(user_id)
    end

    Rails.logger.info '[Migration] Enqueued deduplication jobs for all users'
  rescue StandardError => e
    Rails.logger.error "[Migration] Failed to enqueue deduplication jobs: #{e.message}"
    # Don't fail the migration if Redis/Sidekiq is unavailable
  end
end
