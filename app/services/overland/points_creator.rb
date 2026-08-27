# frozen_string_literal: true

class Overland::PointsCreator
  RETURNING_COLUMNS = Point::UPSERT_RETURNING_COLUMNS

  attr_reader :params, :user_id

  def initialize(params, user_id)
    @params = params
    @user_id = user_id
  end

  def call
    data = Overland::Params.new(params).call
    return [] if data.blank?

    payload = data
              .compact
              .reject { |location| unusable_location?(location) }
              .map { |location| location.merge(user_id:) }
              .uniq { |location| Point.dedup_key(location) }

    result = upsert_points(payload)
    if result.any?
      inserted_count = result.count { |row| row['xmax'].to_i.zero? }
      User.update_counters(user_id, points_count: inserted_count) if inserted_count.positive?
      timestamps = payload.filter_map { |p| p[:timestamp]&.to_i }
      Points::PostIngestActions.new(
        user_id:,
        timestamps:,
        points: result,
        payload:
      ).call
    end

    result
  end

  private

  def unusable_location?(location)
    location[:lonlat].nil? || location[:timestamp].nil? ||
      Points::NullIsland.lonlat?(location[:lonlat])
  end

  def upsert_points(locations)
    created_points = []

    locations.each_slice(1000) do |batch|
      # Dual-write the dimension FK: the backfill only sweeps rows that exist
      # when it passes, and live tracker points land behind its cursor.
      dimension_resolver.stamp(batch)
      result = Point.archival_safe_upsert_all(
        batch,
        returning: Arel.sql(RETURNING_COLUMNS)
      )
      created_points.concat(result) if result
    end

    created_points
  end

  def dimension_resolver
    @dimension_resolver ||= Points::DimensionResolver.new
  end
end
