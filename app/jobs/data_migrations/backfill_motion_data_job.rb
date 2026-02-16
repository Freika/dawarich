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
        # rubocop:disable Rails/SkipsModelValidations
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

    motion = extract_motion_data(raw)
    return if motion.blank?

    { id: point.id, motion_data: motion }
  end

  def extract_motion_data(raw)
    extract_overland_motion(raw) || extract_google_motion(raw) || extract_owntracks_motion(raw) || {}
  end

  def extract_overland_motion(raw)
    props = raw.deep_symbolize_keys[:properties] || {}
    return unless props[:motion] || props[:activity] || props[:action]

    { motion: props[:motion], activity: props[:activity], action: props[:action] }.compact
  end

  def extract_google_motion(raw)
    result = {}
    result['activity'] = raw['activity'] if raw['activity']
    result['activityRecord'] = raw['activityRecord'] if raw['activityRecord']
    result['activities'] = raw['activities'] if raw['activities']
    result['activityType'] = raw['activityType'] if raw['activityType']
    travel_mode = raw.dig('waypointPath', 'travelMode')
    result['travelMode'] = travel_mode if travel_mode
    result.presence
  end

  def extract_owntracks_motion(raw)
    data = raw.deep_symbolize_keys
    return unless data[:m] || data[:_type]

    { m: data[:m], _type: data[:_type] }.compact
  end
end
