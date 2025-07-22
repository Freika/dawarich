# frozen_string_literal: true

class StatsQuery
  def initialize(user)
    @user = user
  end

  def points_stats
    result = user.tracked_points.connection.execute(<<~SQL.squish)
      SELECT#{' '}
        COUNT(*) as total,
        COUNT(reverse_geocoded_at) as geocoded,
        COUNT(CASE WHEN geodata = '{}' THEN 1 END) as without_data
      FROM points#{' '}
      WHERE user_id = #{user.id}
    SQL

    row = result.first

    {
      total: row['total'].to_i,
      geocoded: row['geocoded'].to_i,
      without_data: row['without_data'].to_i
    }
  end

  private

  attr_reader :user
end
