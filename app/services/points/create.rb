# frozen_string_literal: true

class Points::Create
  attr_reader :user, :params

  def initialize(user, params)
    @user = user
    @params = params.to_h
  end

  def call
    data = Points::Params.new(params, user.id).call

    deduplicated_data = data.uniq { |point| dedup_key(point) }

    created_points = []
    inserted_count = 0

    deduplicated_data.each_slice(1000) do |location_batch|
      result = Point.upsert_all(
        location_batch,
        unique_by: %i[lonlat timestamp user_id],
        returning: Arel.sql(
          'id, xmax, timestamp, ST_X(lonlat::geometry) AS longitude, ST_Y(lonlat::geometry) AS latitude'
        )
      )
      inserted_count += result.count { |row| row['xmax'].to_i.zero? }
      created_points.concat(result)
    end

    if created_points.any?
      User.update_counters(user.id, points_count: inserted_count) if inserted_count.positive?
      timestamps = deduplicated_data.filter_map { |p| p[:timestamp]&.to_i }
      Points::AnomalyFilterJob.perform_later(user.id, timestamps.min, timestamps.max) if timestamps.any?
      Tracks::RealtimeDebouncer.new(user.id).trigger
      Points::LiveBroadcaster.new(user.id, created_points, deduplicated_data).call
    end

    created_points
  end

  private

  # Build a dedup key whose equivalence classes match the PostgreSQL
  # UNIQUE index on (lonlat, timestamp, user_id). The raw lonlat WKT
  # string from Points::Params can differ character-by-character for
  # points that collapse to the same geography(Point, 4326) value at
  # double precision (e.g. clients that sometimes stringify floats
  # with extra decimals). Without normalization, `uniq` keeps both
  # variants and the subsequent `Point.upsert_all` fails with
  # `PG::CardinalityViolation: ON CONFLICT DO UPDATE command cannot
  # affect row a second time`, losing the entire 1000-point slice.
  # Rounding to 7 decimal places preserves ~1 cm precision at the
  # equator — well within GPS error — while guaranteeing the Ruby key
  # matches the DB key.
  def dedup_key(point)
    lon, lat = point[:lonlat].to_s.scan(/-?\d+(?:\.\d+)?/).map { |n| n.to_f.round(7) }
    [lon, lat, point[:timestamp].to_i, point[:user_id]]
  end
end
