# frozen_string_literal: true

class DestroyOrphanedTracks < ActiveRecord::Migration[8.0]
  BATCH_SIZE = 1000

  def up
    total = 0

    loop do
      ids = Track.where.missing(:points).limit(BATCH_SIZE).pluck(:id)
      break if ids.empty?

      TrackSegment.where(track_id: ids).delete_all
      total += Track.where(id: ids).delete_all
    end

    Rails.logger.info("[DestroyOrphanedTracks] removed #{total} orphaned tracks")
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Cannot restore deleted orphaned tracks'
  end
end
