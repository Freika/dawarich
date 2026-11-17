# frozen_string_literal: true

class StatsQuery
  def initialize(user)
    @user = user
  end

  def points_stats
    cached_stats = Rails.cache.fetch(Cache::UserKeys.points_geocoded_stats(user.id), expires_in: 1.day) do
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

  # Both are daily-cached counts. The geocoded count is the total minus the
  # points still waiting for geocoding, which the partial index on
  # reverse_geocoded_at IS NULL serves; counting the geocoded rows directly
  # reads every row of the user. The empty-result count has no index and
  # scans, so it is only computed where it is actually rendered: the stats
  # panel is wrapped in DawarichSettings.store_geodata?, so without this guard
  # every Cloud user paid for a scan whose result was never displayed.
  def cached_points_geocoded_stats
    # Clamped: points_count is a counter cache and can briefly run behind.
    stats = { geocoded: [user.points_count.to_i - count_points('reverse_geocoded_at IS NULL'), 0].max }
    return stats unless DawarichSettings.store_geodata?

    # Deliberately not `geodata = '{}'`: geodata is dropped in the points table
    # rewrite. ReverseGeocoding::Points::FetchData stamps reverse_geocoded_at
    # and leaves city/country_name/country_id untouched when the provider
    # returns nothing, so this says the same thing using columns that survive.
    # Both country name columns must be checked too: rows from before
    # country_name superseded the legacy country string carry a name in one of
    # them but no country_id until DataMigrations::BackfillPointCountryIdJob
    # derives it (from COALESCE of the same two columns) — they have data.
    stats[:without_data] = count_points(
      'reverse_geocoded_at IS NOT NULL AND city IS NULL ' \
      'AND country_name IS NULL AND country IS NULL AND country_id IS NULL'
    )

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
