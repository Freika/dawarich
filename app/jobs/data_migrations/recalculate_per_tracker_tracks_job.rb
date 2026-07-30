# frozen_string_literal: true

class DataMigrations::RecalculatePerTrackerTracksJob < ApplicationJob
  queue_as :data_migrations

  STAGGER_WINDOW_SECONDS = 3600

  def perform(user_id = nil)
    return enqueue_pending_users if user_id.nil?

    user = User.find_by(id: user_id)
    return unless user

    # Read deviceTag out of the uploaded Records.json first: the importer never
    # stored it in raw_data, so this is the only accurate source. Whatever it
    # cannot resolve falls through to the raw_data/import-based backfiller.
    backfilled = backfill_google_records_devices(user)
    backfilled += Points::TrackerIdBackfiller.new(user).call

    return unless backfilled.positive? || user.tracks.where(tracker_id: nil).exists?

    Users::RecalculateDataJob.perform_now(user.id, notify: false)
  end

  private

  def backfill_google_records_devices(user)
    user.imports.where(source: :google_records).sum do |import|
      Points::DeviceTagBackfiller.new(import).call
    end
  end

  def enqueue_pending_users
    user_ids = User
               .where(
                 'EXISTS (SELECT 1 FROM tracks WHERE tracks.user_id = users.id AND tracks.tracker_id IS NULL) ' \
                 'OR EXISTS (SELECT 1 FROM points WHERE points.user_id = users.id AND points.tracker_id IN (?))',
                 Points::TrackerIdBackfiller::LEGACY_CONSTANTS
               )
               .pluck(:id)
    return if user_ids.empty?

    Rails.logger.info(
      "[DataMigrations::RecalculatePerTrackerTracks] enqueuing recalculation for #{user_ids.size} user(s)"
    )

    user_ids.each do |id|
      delay = rand(0..STAGGER_WINDOW_SECONDS).seconds
      self.class.set(wait: delay).perform_later(id)
    end
  end
end
