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

    Track.where(id: track_ids).where.missing(:points).find_each(&:destroy)
  end

  def delete_points_in_batches
    total_deleted = 0

    loop do
      ids = @import.points.limit(BATCH_SIZE).pluck(:id)
      break if ids.empty?

      total_deleted += Point.where(id: ids).delete_all
    end

    total_deleted
  end
end
