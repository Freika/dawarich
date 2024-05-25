# frozen_string_literal: true

class Owntracks::PointCreatingJob < ApplicationJob
  queue_as :default

  # TODO: after deprecation of old endpoint, make user_id required
  def perform(point_params, user_id = nil)
    parsed_params = OwnTracks::Params.new(point_params).call

    Point.create!(parsed_params.merge(user_id:))
  end
end
