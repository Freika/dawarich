# frozen_string_literal: true

class Traccar::PointCreator
  RETURNING_COLUMNS = 'id, xmax, timestamp, ST_X(lonlat::geometry) AS longitude, ST_Y(lonlat::geometry) AS latitude'

  attr_reader :params, :user_id

  def initialize(params, user_id)
    @params = params
    @user_id = user_id
  end

  def call
    parsed = Traccar::Params.new(params).call
    return [] if parsed.blank?

    payload = parsed.merge(user_id:)
    return [] if payload[:lonlat].nil? || payload[:timestamp].nil?

    result = upsert_points([payload])
    if result.any?
      inserted_count = result.count { |row| row['xmax'].to_i.zero? }
      User.update_counters(user_id, points_count: inserted_count) if inserted_count.positive?
      timestamps = [payload].filter_map { |p| p[:timestamp]&.to_i }
      Points::AnomalyFilterJob.perform_later(user_id, timestamps.min, timestamps.max) if timestamps.any?
      Tracks::RealtimeDebouncer.new(user_id).trigger
      Points::LiveBroadcaster.new(user_id, result, [payload]).call
    end

    result
  end

  private

  def upsert_points(locations)
    created_points = []

    locations.each_slice(1000) do |batch|
      result = Point.upsert_all(
        batch,
        unique_by: %i[lonlat timestamp user_id],
        returning: Arel.sql(RETURNING_COLUMNS)
      )
      created_points.concat(result) if result
    end

    created_points
  end
end
