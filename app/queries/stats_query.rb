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
      geocoded: cached_stats[:geocoded],
      without_data: cached_stats[:without_data]
    }
  end

  def cached_points_geocoded_stats
    # No index serves these filters since the 2026-08 points index
    # consolidation; both are daily-cached counts that scan the user's rows
    # via the (user_id, ...) composite index. The without_data count retires
    # together with the geodata column.
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

    without_data_sql = ActiveRecord::Base.sanitize_sql_array(
      [
        <<~SQL.squish,
          SELECT COUNT(*) as without_data
          FROM points
          WHERE user_id = ? AND geodata = '{}'::jsonb
        SQL
        user.id
      ]
    )

    geocoded_result = Point.connection.select_value(geocoded_sql)
    without_data_result = Point.connection.select_value(without_data_sql)

    {
      geocoded: geocoded_result.to_i,
      without_data: without_data_result.to_i
    }
  end

  private

  attr_reader :user
end
