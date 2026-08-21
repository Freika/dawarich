# frozen_string_literal: true

class StatsQuery
  def initialize(user)
    @user = user
  end

  def points_stats
    cached_stats = Rails.cache.fetch("dawarich/user_#{user.id}_points_geocoded_stats", expires_in: 1.day) do
      cached_points_geocoded_stats
    end

    total = user.points_count.to_i
    geocoded = cached_stats[:geocoded].to_i

    {
      total: total,
      geocoded: geocoded,
      geocoded_percentage: geocoded_percentage(geocoded, total),
      without_data: cached_stats[:without_data]
    }
  end

  # No index serves these filters since the 2026-08 points index consolidation,
  # so both are daily-cached counts that scan the user's rows via the
  # (user_id, ...) composite index. The empty-result count is only computed
  # where it is actually rendered: the stats panel is wrapped in
  # DawarichSettings.store_geodata?, so without this guard every Cloud user
  # paid for a scan whose result was never displayed.
  def cached_points_geocoded_stats
    stats = { geocoded: count_points('reverse_geocoded_at IS NOT NULL') }
    return stats unless DawarichSettings.store_geodata?

    # Deliberately not `geodata = '{}'`: geodata is dropped in the points table
    # rewrite. ReverseGeocoding::Points::FetchData stamps reverse_geocoded_at
    # and leaves city/country_id untouched when the provider returns nothing,
    # so this says the same thing using columns that survive.
    stats[:without_data] =
      count_points('reverse_geocoded_at IS NOT NULL AND city IS NULL AND country_id IS NULL')

    stats
  end

  private

  attr_reader :user

  def count_points(condition)
    sql = ActiveRecord::Base.sanitize_sql_array(
      ["SELECT COUNT(*) FROM points WHERE user_id = ? AND #{condition}", user.id]
    )

    Point.connection.select_value(sql).to_i
  end

  # Clamped: points_count is a counter cache and can briefly run behind the
  # geocoded count, which would otherwise render as 100.4%.
  def geocoded_percentage(geocoded, total)
    return 0.0 if total.zero?

    [(geocoded * 100.0 / total).round(1), 100.0].min
  end
end
