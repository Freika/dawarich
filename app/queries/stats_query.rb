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
      total: user.points_count,
      geocoded: cached_stats[:geocoded],
      without_data: cached_stats[:without_data]
    }
  end

  private

  attr_reader :user

  def cached_points_geocoded_stats
    sql = ActiveRecord::Base.sanitize_sql_array([
      <<~SQL.squish,
        SELECT
          COUNT(reverse_geocoded_at) as geocoded,
          COUNT(CASE WHEN geodata = '{}'::jsonb THEN 1 END) as without_data
        FROM points
        WHERE user_id = ?
      SQL
      user.id
    ])

    result = Point.connection.select_one(sql)

    {
      geocoded: result['geocoded'].to_i,
      without_data: result['without_data'].to_i
    }
  end
end
