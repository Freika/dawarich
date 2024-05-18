# frozen_string_literal: true

class Owntracks::PointCreatingJob < ApplicationJob
  queue_as :default

  def perform(point_params)
    parsed_params = OwnTracks::Params.new(point_params).call

    Point.create(parsed_params)
  end
end
