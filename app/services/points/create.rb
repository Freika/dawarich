# frozen_string_literal: true

class Points::Create
  attr_reader :user, :params

  def initialize(user, params)
    @user = user
    @params = params.to_h
  end

  def call
    data = Points::Params.new(params, user.id).call

    deduplicated_data = data.uniq { |point| Point.dedup_key(point) }

    # Dual-write the dimension FKs alongside the legacy columns. The backfill
    # only sweeps rows that exist when it passes; without this every new point
    # would land unstamped behind the cursor.
    Points::DimensionResolver.new.stamp(deduplicated_data)

    created_points = []
    inserted_count = 0

    deduplicated_data.each_slice(1000) do |location_batch|
      result = Point.archival_safe_upsert_all(
        location_batch,
        returning: Arel.sql(Point::UPSERT_RETURNING_COLUMNS)
      )
      inserted_count += result.count { |row| row['xmax'].to_i.zero? }
      created_points.concat(result)
    end

    if created_points.any?
      User.update_counters(user.id, points_count: inserted_count) if inserted_count.positive?
      timestamps = deduplicated_data.filter_map { |p| p[:timestamp]&.to_i }
      Points::PostIngestActions.new(
        user_id: user.id,
        timestamps:,
        points: created_points,
        payload: deduplicated_data
      ).call
    end

    created_points
  end
end
