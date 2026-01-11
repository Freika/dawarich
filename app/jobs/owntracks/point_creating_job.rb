# frozen_string_literal: true

class Owntracks::PointCreatingJob < ApplicationJob
  queue_as :points

  def perform(point_params, user_id)
    OwnTracks::PointCreator.new(point_params, user_id).call
  end
end
