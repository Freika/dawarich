# frozen_string_literal: true

class DataMigrations::DestroyOrphanedTracksJob < ApplicationJob
  queue_as :data_migrations

  BATCH_SIZE = 1000

  def perform
    total = 0

    loop do
      ids = Track.where.missing(:points).limit(BATCH_SIZE).pluck(:id)
      break if ids.empty?

      TrackSegment.where(track_id: ids).delete_all
      total += Track.where(id: ids).delete_all
    end

    Rails.logger.info("[DestroyOrphanedTracksJob] removed #{total} orphaned tracks")
  end
end
