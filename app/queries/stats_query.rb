# frozen_string_literal: true

class StatsQuery
  def initialize(user)
    @user = user
  end

  def points_stats
    cached_stats = Rails.cache.fetch("dawarich/user_#{user.id}_points_geocoded_stats", expires_in: 1.day) do
      cached_points_geocoded_stats
    end

    {
      total: user.points_count.to_i,
      geocoded: cached_stats[:geocoded]
    }
  end

  def cached_points_geocoded_stats
    # No index serves this filter since the 2026-08 points index consolidation;
    # it is a daily-cached count that scans the user's rows via the
    # (user_id, ...) composite index.
    geocoded_sql = ActiveRecord::Base.sanitize_sql_array(
      [
        <<~SQL.squish,
          SELECT COUNT(*) as geocoded
          FROM points
          WHERE user_id = ? AND reverse_geocoded_at IS NOT NULL
        SQL
        user.id
      ]
    )

    { geocoded: Point.connection.select_value(geocoded_sql).to_i }
  end

  private

  attr_reader :user
end
