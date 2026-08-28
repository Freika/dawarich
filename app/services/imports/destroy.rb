# frozen_string_literal: true

class Imports::Destroy
  BATCH_SIZE = 5000

  attr_reader :user, :import

  def initialize(user, import)
    @user = user
    @import = import
  end

  def call
    track_ids = @import.points.where.not(track_id: nil).distinct.pluck(:track_id)

    EnhancedImport::Destroy.new(@import).call

    total_deleted = delete_points_in_batches
    User.update_counters(@user.id, points_count: -total_deleted) if total_deleted.positive?

    @import.destroy!

    destroy_orphaned_tracks(track_ids)

    Rails.logger.info "Import #{@import.id} deleted with #{total_deleted} points"

    Stats::BulkCalculator.new(@user.id).call
  end

  private

  def destroy_orphaned_tracks(track_ids)
    return if track_ids.empty?

    orphaned_ids = Track.where(id: track_ids).where.missing(:points).pluck(:id)
    Track.delete_orphaned(orphaned_ids)
  end

  def delete_points_in_batches
    total_deleted = 0

    loop do
      # delete_all returns no rows, so capture the timestamps BEFORE deleting —
      # the tile epoch needs to know which years the deletion touched.
      rows = @import.points.limit(BATCH_SIZE).pluck(:id, :timestamp)
      break if rows.empty?

      # Collapsing to one timestamp per year keeps the bump to one write per
      # touched year.
      timestamp_per_year = {}
      rows.each do |(_id, timestamp)|
        timestamp_per_year[Points::TileEpoch.year_for(timestamp)] ||= timestamp
      end
      deleted = Point.where(id: rows.map(&:first)).delete_all
      total_deleted += deleted

      # Bumping per batch keeps tiles honest even when a later batch dies:
      # a retry re-plucks only the rows that survived, so the years already
      # deleted here would otherwise never be invalidated.
      Points::TileEpoch.bump(@user.id, timestamps: timestamp_per_year.values) if deleted.positive?
    end

    total_deleted
  end
end
