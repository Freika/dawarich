# frozen_string_literal: true

class StatsQuery
  def initialize(user)
    @user = user
  end

  def points_stats
    sql = ActiveRecord::Base.sanitize_sql_array([
      <<~SQL.squish,
        SELECT
          COUNT(id) as total,
          COUNT(reverse_geocoded_at) as geocoded,
          COUNT(CASE WHEN geodata = '{}'::jsonb THEN 1 END) as without_data
        FROM points
        WHERE user_id = ?
      SQL
      user.id
    ])

    result = Point.connection.select_one(sql)

    {
      total: result['total'].to_i,
      geocoded: result['geocoded'].to_i,
      without_data: result['without_data'].to_i
    }
  end

  private

  attr_reader :user
end
