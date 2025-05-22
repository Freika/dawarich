# frozen_string_literal: true

class Owntracks::PointCreatingJob < ApplicationJob
  include PointValidation

  queue_as :points

  def perform(point_params, user_id)
    parsed_params = OwnTracks::Params.new(point_params).call

    return if parsed_params[:timestamp].nil? || parsed_params[:lonlat].nil?
    return if point_exists?(parsed_params, user_id)

    Point.create!(parsed_params.merge(user_id:))
  end
end
