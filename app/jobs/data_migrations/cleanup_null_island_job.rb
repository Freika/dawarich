# frozen_string_literal: true

class DataMigrations::CleanupNullIslandJob < ApplicationJob
  queue_as :data_migrations

  def perform(user_id = nil)
    return fan_out if user_id.nil?

    user = find_user_or_skip(user_id) || return

    rows = user.points.null_island.pluck(:id, :timestamp, :track_id)
    track_ids = rows.filter_map(&:last).uniq
    affected_months = rows.map do |_, timestamp, _|
      time = Time.zone.at(timestamp)
      [time.year, time.month]
    end.uniq

    Point.where(id: rows.map(&:first)).update_all(anomaly: true, updated_at: Time.current) if rows.any?
    destroyed_visits = destroy_null_island_visits(user)

    Rails.logger.info(
      "[DataMigrations::CleanupNullIsland] user_id=#{user.id} flagged=#{rows.size} " \
      "visits_destroyed=#{destroyed_visits} tracks=#{track_ids.size} months=#{affected_months.size}"
    )

    affected_months.each { |year, month| Stats::CalculatingJob.perform_later(user.id, year, month) }
    track_ids.each { |track_id| Tracks::RecalculateJob.perform_later(track_id) }
  end

  private

  def fan_out
    User.where(id: Point.null_island.select(:user_id).distinct)
        .pluck(:id)
        .each { |user_id| self.class.perform_later(user_id) }
  end

  def destroy_null_island_visits(user)
    user.visits
        .joins(:place)
        .where(Points::NullIsland.sql_predicate('places.lonlat'))
        .destroy_all
        .count
  end
end
