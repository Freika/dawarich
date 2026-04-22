# frozen_string_literal: true

class Points::Create
  attr_reader :user, :params

  def initialize(user, params)
    @user = user
    @params = params.to_h
  end

  def call
    data = Points::Params.new(params, user.id).call

    deduplicated_data = data.uniq { |point| [point[:lonlat], point[:timestamp].to_i, point[:user_id]] }

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
      evaluate_geofences(created_points)
    end

    created_points
  end

  private

  def evaluate_geofences(created_points)
    point_ids = created_points.map { |row| row['id'] }.compact
    return if point_ids.empty?

    Point.where(id: point_ids).find_each do |point|
      GeofenceEvents::Evaluator::ForPoint.call(user, point)
    end
  end
end
