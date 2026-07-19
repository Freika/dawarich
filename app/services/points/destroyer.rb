# frozen_string_literal: true

class Points::Destroyer
  def initialize(user, point_ids)
    @user = user
    @point_ids = Array(point_ids)
  end

  def call
    destroyed = nil

    ActiveRecord::Base.transaction do
      destroyed = user.points.where(id: point_ids).without_raw_data.destroy_all
    end

    return destroyed if destroyed.empty?

    User.update_counters(user.id, points_count: -destroyed.count)

    enqueue_stats_recalculation(destroyed)
    enqueue_track_recalculation(destroyed)

    destroyed
  end

  private

  attr_reader :user, :point_ids

  def enqueue_stats_recalculation(destroyed)
    destroyed
      .map { |point| Time.zone.at(point.timestamp) }
      .map { |time| [time.year, time.month] }
      .uniq
      .each do |year, month|
        Rails.logger.info("[Points::Destroyer] enqueuing Stats::CalculatingJob for #{year}-#{month}")
        Stats::CalculatingJob.perform_later(user.id, year, month)
      end
  end

  def enqueue_track_recalculation(destroyed)
    track_ids = destroyed.filter_map(&:track_id).uniq
    return if track_ids.empty?

    Rails.logger.info(
      "[Points::Destroyer] deleted #{destroyed.count} points, " \
      "enqueuing Tracks::RecalculateJob for #{track_ids.size} tracks: #{track_ids.inspect}"
    )
    track_ids.each { |track_id| Tracks::RecalculateJob.perform_later(track_id) }
  end
end
