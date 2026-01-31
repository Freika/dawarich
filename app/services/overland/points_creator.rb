# frozen_string_literal: true

class Overland::PointsCreator
  RETURNING_COLUMNS = 'id, timestamp, ST_X(lonlat::geometry) AS longitude, ST_Y(lonlat::geometry) AS latitude'

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
              .reject { |location| location[:lonlat].nil? || location[:timestamp].nil? }
              .map { |location| location.merge(user_id:) }

    result = upsert_points(payload)
    if result.any?
      User.reset_counters(user_id, :points)
      Tracks::RealtimeDebouncer.new(user_id).trigger
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
