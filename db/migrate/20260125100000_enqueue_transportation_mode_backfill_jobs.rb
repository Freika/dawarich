# frozen_string_literal: true

class EnqueueTransportationModeBackfillJobs < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  # Stagger jobs to avoid overwhelming the queue
  USER_DELAY_SECONDS = 30
  IMPORT_DELAY_SECONDS = 10
  INITIAL_DELAY_MINUTES = 2

  def up
    enqueue_user_backfill_jobs
    enqueue_import_backfill_jobs
  end

  def down
    # Jobs may have already run; nothing to reverse
  end

  private

  def enqueue_user_backfill_jobs
    user_ids = User.pluck(:id)
    return if user_ids.empty?

    Rails.logger.info "[Migration] Enqueuing BackfillJob for #{user_ids.size} users"

    user_ids.each_with_index do |user_id, index|
      delay = INITIAL_DELAY_MINUTES.minutes + (index * USER_DELAY_SECONDS).seconds
      TransportationModes::BackfillJob.set(wait: delay).perform_later(user_id)
    end

    Rails.logger.info "[Migration] Enqueued BackfillJob for all users"
  rescue StandardError => e
    Rails.logger.error "[Migration] Failed to enqueue BackfillJob: #{e.message}"
    # Don't fail the migration if Redis/Sidekiq is unavailable
  end

  def enqueue_import_backfill_jobs
    supported_sources = %w[
      google_semantic_history
      google_phone_takeout
      google_records
      owntracks
      geojson
    ]

    import_ids = Import.where(source: supported_sources).pluck(:id)
    return if import_ids.empty?

    Rails.logger.info "[Migration] Enqueuing ImportBackfillJob for #{import_ids.size} imports"

    # Start import jobs after user jobs have a head start
    base_delay = INITIAL_DELAY_MINUTES.minutes + (User.count * USER_DELAY_SECONDS).seconds

    import_ids.each_with_index do |import_id, index|
      delay = base_delay + (index * IMPORT_DELAY_SECONDS).seconds
      TransportationModes::ImportBackfillJob.set(wait: delay).perform_later(import_id)
    end

    Rails.logger.info "[Migration] Enqueued ImportBackfillJob for all imports"
  rescue StandardError => e
    Rails.logger.error "[Migration] Failed to enqueue ImportBackfillJob: #{e.message}"
    # Don't fail the migration if Redis/Sidekiq is unavailable
  end
end
