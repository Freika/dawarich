# frozen_string_literal: true

class OwnTracks::PointCreator
  RETURNING_COLUMNS = 'id, timestamp, ST_X(lonlat::geometry) AS longitude, ST_Y(lonlat::geometry) AS latitude'

  attr_reader :params, :user_id

  def initialize(params, user_id)
    @params = params
    @user_id = user_id
  end

  def call
    parsed_params = OwnTracks::Params.new(params).call
    return [] if parsed_params.blank?

    payload = parsed_params.merge(user_id:)
    return [] if payload[:timestamp].nil? || payload[:lonlat].nil?

    result = upsert_points([payload])
    if result.any?
      User.reset_counters(user_id, :points)
      Tracks::RealtimeDebouncer.new(user_id).trigger
      Points::LiveBroadcaster.new(user_id, result, [payload]).call
    end

    result
  end

  private

  def upsert_points(locations)
    created_points = []

    locations.each_slice(1000) do |batch|
      # rubocop:disable Rails/SkipsModelValidations
      result = Point.upsert_all(
        batch,
        unique_by: %i[lonlat timestamp user_id],
        returning: Arel.sql(RETURNING_COLUMNS)
      )
      # rubocop:enable Rails/SkipsModelValidations
      created_points.concat(result) if result
    end

    created_points
  end
end
