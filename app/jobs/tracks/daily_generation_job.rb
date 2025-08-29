# frozen_string_literal: true

# Daily job to handle bulk track processing for users with recent activity
# This serves as a backup to incremental processing and handles any missed tracks
class Tracks::DailyGenerationJob < ApplicationJob
  queue_as :tracks

  def perform
    Rails.logger.info "Starting daily track generation for users with recent activity"
    
    users_with_recent_activity.find_each do |user|
      process_user_tracks(user)
    end

    Rails.logger.info "Completed daily track generation"
  end

  private

  def users_with_recent_activity
    # Find users who have created points in the last 2 days
    # This gives buffer to handle cross-day tracks
    User.joins(:points)
        .where(points: { created_at: 2.days.ago..Time.current })
        .distinct
  end

  def process_user_tracks(user)
    # Process tracks for the last 2 days with buffer
    start_at = 3.days.ago.beginning_of_day  # Extra buffer for cross-day tracks
    end_at = Time.current

    Rails.logger.info "Enqueuing daily track generation for user #{user.id}"

    Tracks::ParallelGeneratorJob.perform_later(
      user.id,
      start_at: start_at,
      end_at: end_at,
      mode: :daily,
      chunk_size: 6.hours  # Smaller chunks for recent data processing
    )
  rescue StandardError => e
    Rails.logger.error "Failed to enqueue daily track generation for user #{user.id}: #{e.message}"
    ExceptionReporter.call(e, "Daily track generation failed for user #{user.id}")
  end
end