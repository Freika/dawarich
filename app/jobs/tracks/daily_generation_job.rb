# frozen_string_literal: true

# Daily job to handle bulk track processing for users with recent activity
# This serves as a backup to incremental processing and handles any missed tracks
class Tracks::DailyGenerationJob < ApplicationJob
  queue_as :tracks

  def perform
    # Compute time window once at job start to ensure consistency
    time_window = compute_time_window

    Rails.logger.info 'Starting daily track generation for users with recent activity'

    users_processed = 0
    users_failed = 0

    begin
      users_with_recent_activity(time_window).find_each do |user|
        if process_user_tracks(user, time_window)
          users_processed += 1
        else
          users_failed += 1
        end
      end
    rescue StandardError => e
      Rails.logger.error "Critical failure in daily track generation: #{e.message}"
      ExceptionReporter.call(e, 'Daily track generation job failed')
      raise
    end

    Rails.logger.info "Completed daily track generation: #{users_processed} users processed, #{users_failed} users failed"
  end

  private

  def compute_time_window
    now = Time.current
    {
      activity_window_start: 2.days.ago(now),
      activity_window_end: now,
      processing_start: 3.days.ago(now).beginning_of_day,
      processing_end: now
    }
  end

  def users_with_recent_activity(time_window)
    # Find users who have created points within the activity window
    # This gives buffer to handle cross-day tracks
    user_ids = Point.where(
      created_at: time_window[:activity_window_start]..time_window[:activity_window_end]
    ).select(:user_id).distinct

    User.where(id: user_ids)
  end

  def process_user_tracks(user, time_window)
    Rails.logger.info "Enqueuing daily track generation for user #{user.id}"

    Tracks::ParallelGeneratorJob.perform_later(
      user.id,
      start_at: time_window[:processing_start],
      end_at: time_window[:processing_end],
      mode: :daily,
      chunk_size: 6.hours
    )

    true
  rescue StandardError => e
    Rails.logger.error "Failed to enqueue daily track generation for user #{user.id}: #{e.message}"
    ExceptionReporter.call(e, "Daily track generation failed for user #{user.id}")
    false
  end
end
