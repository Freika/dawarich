# frozen_string_literal: true

class Points::Create
  attr_reader :user, :params

  def initialize(user, params)
    @user = user
    @params = params.to_h
  end

  def call
    data = Points::Params.new(params, user.id).call

    created_points = []

    data.each_slice(1000) do |location_batch|
      # rubocop:disable Rails/SkipsModelValidations
      result = Point.upsert_all(
        location_batch,
        unique_by: %i[lonlat timestamp user_id],
        returning: Arel.sql('id, timestamp, ST_X(lonlat::geometry) AS longitude, ST_Y(lonlat::geometry) AS latitude')
      )
      # rubocop:enable Rails/SkipsModelValidations

      created_points.concat(result)
    end

    created_points
  end
end
