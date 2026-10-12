# frozen_string_literal: true

class DestroyOrphanedTracks < ActiveRecord::Migration[8.0]
  def up
    DataMigrations::DestroyOrphanedTracksJob.perform_later
  rescue StandardError => e
    Rails.logger.warn "[Migration] Could not enqueue DestroyOrphanedTracksJob: #{e.message}"
  end

  def down
    # no-op: orphaned tracks were removed asynchronously and cannot be restored
  end
end
