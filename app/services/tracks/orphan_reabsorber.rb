# frozen_string_literal: true

module Tracks
  class OrphanReabsorber
    FRESHNESS_BUFFER = 60.seconds
    LOOKBACK = 6.hours

    attr_reader :user

    def initialize(user)
      @user = user
    end

    def call
      return 0 unless untracked_points_in_lookback?

      user.tracks
          .where('end_at >= ?', LOOKBACK.ago)
          .find_each
          .sum { |track| absorb_orphans_into(track) }
    end

    private

    def untracked_points_in_lookback?
      user.points
          .where(track_id: nil)
          .where('anomaly IS NOT TRUE')
          .where('timestamp >= ?', LOOKBACK.ago.to_i)
          .where(created_at: ...FRESHNESS_BUFFER.ago)
          .exists?
    end

    def absorb_orphans_into(track)
      orphan_ids = orphan_point_ids_for(track)
      return 0 if orphan_ids.empty?

      succeeded = false
      ActiveRecord::Base.transaction(requires_new: true) do
        Point.where(id: orphan_ids).update_all(track_id: track.id)

        bounds = Point.where(track_id: track.id).pick(Arel.sql('MIN(timestamp), MAX(timestamp)'))
        raise ActiveRecord::Rollback if bounds.nil?

        new_start = Time.zone.at(bounds[0])
        new_end = Time.zone.at(bounds[1])

        if track.start_at != new_start || track.end_at != new_end
          track.update!(start_at: new_start, end_at: new_end)
        else
          track.recalculate_path_and_distance!
        end

        succeeded = true
      end

      succeeded ? orphan_ids.size : 0
    rescue ActiveRecord::RecordNotUnique
      Rails.logger.warn(
        'event=tracks.reabsorb_orphan_points_failed reason=unique_violation ' \
        "user_id=#{user.id} track_id=#{track.id} orphan_ids=#{orphan_ids.join(',')}"
      )
      0
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn(
        'event=tracks.reabsorb_orphan_points_failed reason=invalid ' \
        "user_id=#{user.id} track_id=#{track.id} orphan_ids=#{orphan_ids.join(',')} " \
        "error=#{e.message}"
      )
      0
    end

    def orphan_point_ids_for(track)
      Point.not_held_by_extraction.where(user_id: user.id)
           .where('COALESCE(tracker_id, ?) = COALESCE(?, ?)', '', track.tracker_id, '')
           .where(track_id: nil)
           .where('anomaly IS NOT TRUE')
           .where(timestamp: track.start_at.to_i..track.end_at.to_i)
           .where(created_at: ...FRESHNESS_BUFFER.ago)
           .pluck(:id)
    end
  end
end
