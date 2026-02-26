# frozen_string_literal: true

class DataMigrations::BackfillMotionDataJob < ApplicationJob
  queue_as :data_migrations

  BATCH_SIZE = 1000

  def perform(batch_size: BATCH_SIZE)
    Rails.logger.info('Starting motion_data backfill job')

    processed = 0

    Point.where(motion_data: {}).where.not(raw_data: {}).find_in_batches(batch_size: batch_size) do |points|
      updates = points.filter_map { |point| build_update(point) }

      if updates.any?
        Point.upsert_all(updates, unique_by: :id, update_only: [:motion_data])
        # rubocop:enable Rails/SkipsModelValidations
      end

      processed += points.size
      Rails.logger.info("Backfilled motion_data for #{processed} points")
    end

    Rails.logger.info("Completed motion_data backfill job. Processed #{processed} points")
  end

  private

  def build_update(point)
    raw = point.raw_data
    return unless raw.is_a?(Hash) && raw.present?

    motion = Points::MotionDataExtractor.from_raw_data(raw)
    return if motion.blank?

    { id: point.id, motion_data: motion }
  end
end
