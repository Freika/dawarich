# frozen_string_literal: true

class Owntracks::PointCreatingJob < ApplicationJob
  queue_as :default

  # TODO: after deprecation of old endpoint, make user_id required
  def perform(point_params, user_id = nil)
    parsed_params = OwnTracks::Params.new(point_params).call

    return if point_exists?(parsed_params, user_id)

    Point.create!(parsed_params.merge(user_id:))
  end

  def point_exists?(params, user_id)
    Point.exists?(
      latitude: params[:latitude],
      longitude: params[:longitude],
      timestamp: params[:timestamp],
      user_id:
    )
  end
end
